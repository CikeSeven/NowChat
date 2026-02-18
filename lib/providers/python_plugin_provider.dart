import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:now_chat/core/models/python_execution_result.dart';
import 'package:now_chat/core/models/python_plugin_manifest.dart';
import 'package:now_chat/core/plugin/python_plugin_service.dart';
import 'package:now_chat/util/app_logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PythonPluginInstallState {
  notInstalled,
  downloading,
  installing,
  ready,
  broken,
}

/// Python 插件状态管理：负责安装、卸载、执行与本地状态恢复。
class PythonPluginProvider with ChangeNotifier {
  static const String defaultManifestUrl =
      'https://raw.githubusercontent.com/CikeSeven/NowChat/main/plugin_manifest.json';

  static const _kInstallState = 'python_plugin_install_state';
  static const _kCoreVersion = 'python_plugin_core_version';
  static const _kCoreTargetDir = 'python_plugin_core_target_dir';
  static const _kCoreEntryPoint = 'python_plugin_core_entry_point';
  static const _kInstalledLibraries = 'python_plugin_installed_libraries';

  final PythonPluginService _service;

  PythonPluginInstallState _installState = PythonPluginInstallState.notInstalled;
  PythonPluginManifest? _manifest;
  String _manifestUrl = defaultManifestUrl;
  String? _coreVersion;
  String? _coreTargetDir;
  String? _coreEntryPoint;
  final Map<String, InstalledPythonLibrary> _installedLibraries =
      <String, InstalledPythonLibrary>{};

  double _downloadProgress = 0;
  bool _isInitialized = false;
  bool _isExecuting = false;
  String? _lastError;
  PythonExecutionResult? _lastExecutionResult;
  Directory? _pluginRootDir;
  Directory? _runtimeWorkDir;

  PythonPluginProvider({PythonPluginService? service})
    : _service = service ?? PythonPluginService() {
    unawaited(_initialize());
  }

  PythonPluginInstallState get installState => _installState;
  PythonPluginManifest? get manifest => _manifest;
  String? get coreVersion => _coreVersion;
  double get downloadProgress => _downloadProgress;
  bool get isExecuting => _isExecuting;
  bool get isInitialized => _isInitialized;
  String? get lastError => _lastError;
  PythonExecutionResult? get lastExecutionResult => _lastExecutionResult;
  List<InstalledPythonLibrary> get installedLibraries =>
      _installedLibraries.values.toList();

  bool get isBusy =>
      _installState == PythonPluginInstallState.downloading ||
      _installState == PythonPluginInstallState.installing;

  bool get isCoreReady =>
      Platform.isAndroid
          ? _installState != PythonPluginInstallState.broken
          : _installState == PythonPluginInstallState.ready &&
              (_coreVersion?.isNotEmpty ?? false);

  bool get hasManifest => _manifest != null;

  bool get hasCoreUpdate {
    final core = _manifest?.core;
    if (core == null || _coreVersion == null) return false;
    return _coreVersion != core.version;
  }

  String? get pythonBinaryPath {
    if (Platform.isAndroid) return null;
    if (!isCoreReady || _pluginRootDir == null) return null;
    if ((_coreTargetDir ?? '').isEmpty || (_coreEntryPoint ?? '').isEmpty) {
      return null;
    }
    return _joinPaths(
      _pluginRootDir!.path,
      _coreTargetDir!,
      _coreEntryPoint!,
    );
  }

  Future<void> refreshManifest() async {
    _lastError = null;
    notifyListeners();
    try {
      // 插件中心不再暴露清单地址编辑，统一使用内置远端地址。
      _manifestUrl = defaultManifestUrl;
      final fetchedManifest = await _service.fetchManifest(_manifestUrl);
      _manifest = fetchedManifest;
      if (Platform.isAndroid) {
        _coreVersion = fetchedManifest.core.version;
        _installState = PythonPluginInstallState.ready;
      }
      notifyListeners();
    } catch (e, stackTrace) {
      _lastError = '清单加载失败: $e';
      AppLogger.e('刷新 Python 插件清单失败', e, stackTrace);
      notifyListeners();
    }
  }

  Future<void> installCore() async {
    if (!Platform.isAndroid) {
      _lastError = '当前仅支持 Android 平台';
      notifyListeners();
      return;
    }

    _downloadProgress = 1;
    _lastError = null;
    _installState = PythonPluginInstallState.installing;
    notifyListeners();
    try {
      final manifestCore = _manifest?.core;
      _installState = PythonPluginInstallState.ready;
      _coreVersion = manifestCore?.version ?? 'chaquopy-embedded';
      _coreTargetDir = null;
      _coreEntryPoint = null;
      _downloadProgress = 1;
      await _saveLocalState();
    } catch (e, stackTrace) {
      _installState = PythonPluginInstallState.broken;
      _lastError = '核心包安装失败: $e';
      AppLogger.e('安装 Python 核心包失败', e, stackTrace);
    } finally {
      notifyListeners();
    }
  }

  Future<void> uninstallCore() async {
    if (_pluginRootDir == null) return;
    _lastError = null;
    notifyListeners();
    try {
      if (!Platform.isAndroid && (_coreTargetDir ?? '').isNotEmpty) {
        await _service.uninstallByRelativeDir(
          pluginRootDir: _pluginRootDir!,
          relativeTargetDir: _coreTargetDir!,
        );
      }
      for (final library in _installedLibraries.values) {
        await _service.uninstallByRelativeDir(
          pluginRootDir: _pluginRootDir!,
          relativeTargetDir: library.targetDir,
        );
      }
      _installedLibraries.clear();
      _coreVersion = null;
      _coreTargetDir = null;
      _coreEntryPoint = null;
      _installState = PythonPluginInstallState.notInstalled;
      _downloadProgress = 0;
      await _saveLocalState();
    } catch (e, stackTrace) {
      _installState = PythonPluginInstallState.broken;
      _lastError = '卸载核心包失败: $e';
      AppLogger.e('卸载 Python 核心包失败', e, stackTrace);
    } finally {
      notifyListeners();
    }
  }

  Future<void> installLibrary(String libraryId) async {
    if (_pluginRootDir == null) return;
    PythonPluginPackage? libraryPackage;
    for (final item in _manifest?.libraries ?? const <PythonPluginPackage>[]) {
      if (item.id == libraryId) {
        libraryPackage = item;
        break;
      }
    }
    if (libraryPackage == null) {
      _lastError = '找不到指定库包：$libraryId';
      notifyListeners();
      return;
    }
    _lastError = null;
    _downloadProgress = 0;
    _installState = PythonPluginInstallState.installing;
    notifyListeners();
    try {
      await _service.installPackage(
        package: libraryPackage,
        pluginRootDir: _pluginRootDir!,
        onProgress: (progress) {
          _downloadProgress = progress;
          notifyListeners();
        },
      );
      _installedLibraries[libraryPackage.id] = InstalledPythonLibrary(
        id: libraryPackage.id,
        version: libraryPackage.version,
        targetDir: libraryPackage.targetDir,
        pythonPathEntries: libraryPackage.pythonPathEntries,
      );
      _installState = isCoreReady
          ? PythonPluginInstallState.ready
          : PythonPluginInstallState.notInstalled;
      _downloadProgress = 1;
      await _saveLocalState();
    } catch (e, stackTrace) {
      _installState = PythonPluginInstallState.broken;
      _lastError = '库包安装失败: $e';
      AppLogger.e('安装 Python 库包失败', e, stackTrace);
    } finally {
      notifyListeners();
    }
  }

  Future<void> uninstallLibrary(String libraryId) async {
    if (_pluginRootDir == null) return;
    final library = _installedLibraries[libraryId];
    if (library == null) return;
    _lastError = null;
    notifyListeners();
    try {
      await _service.uninstallByRelativeDir(
        pluginRootDir: _pluginRootDir!,
        relativeTargetDir: library.targetDir,
      );
      _installedLibraries.remove(libraryId);
      await _saveLocalState();
    } catch (e, stackTrace) {
      _lastError = '卸载库包失败: $e';
      AppLogger.e('卸载 Python 库包失败', e, stackTrace);
    } finally {
      notifyListeners();
    }
  }

  Future<void> executeCode(String code, {Duration? timeout}) async {
    final normalizedCode = code.trim();
    if (normalizedCode.isEmpty) return;
    if (!isCoreReady) {
      _lastError = '请先安装 Python 核心包';
      notifyListeners();
      return;
    }
    if (_runtimeWorkDir == null) return;
    _isExecuting = true;
    _lastError = null;
    _lastExecutionResult = null;
    notifyListeners();
    try {
      final env = <String, String>{};
      final pythonPathParts = <String>[];
      for (final library in _installedLibraries.values) {
        final baseDir = _joinPaths(_pluginRootDir!.path, library.targetDir);
        for (final relativeEntry in library.pythonPathEntries) {
          pythonPathParts.add(_joinPaths(baseDir, relativeEntry));
        }
      }
      if (pythonPathParts.isNotEmpty) {
        env['PYTHONPATH'] = pythonPathParts.join(Platform.pathSeparator);
      }

      final result = await _service.executeCode(
        pythonBinaryPath: pythonBinaryPath,
        code: normalizedCode,
        timeout: timeout ?? const Duration(seconds: 20),
        extraSysPaths: pythonPathParts,
        environment: env.isEmpty ? null : env,
        workingDirectory: _runtimeWorkDir!.path,
      );
      _lastExecutionResult = result;
      if (result.timedOut) {
        _lastError = '执行超时（${(timeout ?? const Duration(seconds: 20)).inSeconds} 秒）';
      }
    } catch (e, stackTrace) {
      _lastError = '执行失败: $e';
      AppLogger.e('执行 Python 代码失败', e, stackTrace);
      if (!Platform.isAndroid &&
          (pythonBinaryPath == null || !File(pythonBinaryPath!).existsSync())) {
        _installState = PythonPluginInstallState.broken;
      }
    } finally {
      _isExecuting = false;
      notifyListeners();
    }
  }

  void clearExecutionResult() {
    _lastExecutionResult = null;
    _lastError = null;
    notifyListeners();
  }

  Future<void> _initialize() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      _pluginRootDir = Directory(
        '${supportDir.path}${Platform.pathSeparator}python_plugin',
      );
      if (!_pluginRootDir!.existsSync()) {
        await _pluginRootDir!.create(recursive: true);
      }
      _runtimeWorkDir = Directory(
        '${_pluginRootDir!.path}${Platform.pathSeparator}runtime',
      );
      if (!_runtimeWorkDir!.existsSync()) {
        await _runtimeWorkDir!.create(recursive: true);
      }
      await _loadLocalState();
      if (Platform.isAndroid) {
        // Android 使用 Chaquopy 内置 Python 运行时，核心始终可用。
        _installState = PythonPluginInstallState.ready;
        _coreVersion ??= 'chaquopy-embedded';
        _coreTargetDir = null;
        _coreEntryPoint = null;
      }
      final binaryPath = pythonBinaryPath;
      if (!Platform.isAndroid &&
          isCoreReady &&
          (binaryPath == null || !File(binaryPath).existsSync())) {
        _installState = PythonPluginInstallState.broken;
        _lastError = '检测到核心包文件缺失，请重新安装核心包';
      }
      await refreshManifest();
    } catch (e, stackTrace) {
      _installState = PythonPluginInstallState.broken;
      _lastError = '插件初始化失败: $e';
      AppLogger.e('初始化 Python 插件失败', e, stackTrace);
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> _loadLocalState() async {
    final prefs = await SharedPreferences.getInstance();
    _manifestUrl = defaultManifestUrl;
    _coreVersion = prefs.getString(_kCoreVersion)?.trim();
    _coreTargetDir = prefs.getString(_kCoreTargetDir)?.trim();
    _coreEntryPoint = prefs.getString(_kCoreEntryPoint)?.trim();
    final stateRaw = prefs.getString(_kInstallState)?.trim();
    final parsedState = PythonPluginInstallState.values.where((item) {
      return item.name == stateRaw;
    });
    _installState =
        parsedState.isNotEmpty
            ? parsedState.first
            : ((_coreVersion?.isNotEmpty ?? false)
                ? PythonPluginInstallState.ready
                : PythonPluginInstallState.notInstalled);

    _installedLibraries.clear();
    final libsRaw = prefs.getString(_kInstalledLibraries);
    if (libsRaw != null && libsRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(libsRaw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is! Map) continue;
            final library = InstalledPythonLibrary.fromJson(
              Map<String, dynamic>.from(item),
            );
            _installedLibraries[library.id] = library;
          }
        }
      } catch (_) {
        // 历史脏数据不阻断初始化，忽略并继续。
      }
    }
  }

  Future<void> _saveLocalState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kInstallState, _installState.name);
    if ((_coreVersion ?? '').isEmpty) {
      await prefs.remove(_kCoreVersion);
    } else {
      await prefs.setString(_kCoreVersion, _coreVersion!);
    }
    if ((_coreTargetDir ?? '').isEmpty) {
      await prefs.remove(_kCoreTargetDir);
    } else {
      await prefs.setString(_kCoreTargetDir, _coreTargetDir!);
    }
    if ((_coreEntryPoint ?? '').isEmpty) {
      await prefs.remove(_kCoreEntryPoint);
    } else {
      await prefs.setString(_kCoreEntryPoint, _coreEntryPoint!);
    }
    final librariesPayload =
        _installedLibraries.values.map((item) => item.toJson()).toList();
    await prefs.setString(_kInstalledLibraries, jsonEncode(librariesPayload));
  }

  String _joinPaths(String first, [String? second, String? third]) {
    final parts = <String>[first];
    if (second != null && second.trim().isNotEmpty) {
      parts.add(second.trim());
    }
    if (third != null && third.trim().isNotEmpty) {
      parts.add(third.trim());
    }
    return p.normalize(p.joinAll(parts));
  }
}
