import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:now_chat/core/models/plugin_install_record.dart';
import 'package:now_chat/core/models/plugin_manifest_v2.dart';
import 'package:now_chat/core/models/plugin_ui_runtime.dart';
import 'package:now_chat/core/models/python_execution_result.dart';
import 'package:now_chat/core/plugin/plugin_hook_bus.dart';
import 'package:now_chat/core/plugin/plugin_registry.dart';
import 'package:now_chat/core/plugin/plugin_runtime_executor.dart';
import 'package:now_chat/core/plugin/plugin_service.dart';
import 'package:now_chat/core/plugin/python_plugin_service.dart';
import 'package:now_chat/util/app_logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 插件安装状态。
enum PluginInstallState {
  notInstalled,
  installing,
  ready,
  broken,
}

/// 通用插件状态管理：安装、启用、工具开关、动作执行与 Hook 同步。
class PluginProvider with ChangeNotifier, WidgetsBindingObserver {
  static const String defaultManifestUrl =
      'https://raw.githubusercontent.com/CikeSeven/NowChat/main/plugin_manifest.json';

  static const String recordsStorageKey = 'plugin_registry_records_v2';

  static const _kManifestUrl = 'plugin_registry_manifest_url_v2';
  static const _kLastError = 'plugin_registry_last_error_v2';

  final PluginService _pluginService;
  final PythonPluginService _pythonService;

  String _manifestUrl = defaultManifestUrl;
  PluginManifestV2? _manifest;
  final Map<String, PluginDefinition> _localPluginsById =
      <String, PluginDefinition>{};
  final Map<String, InstalledPluginRecord> _installedRecords =
      <String, InstalledPluginRecord>{};
  final Map<String, PluginInstallState> _pluginStates =
      <String, PluginInstallState>{};
  final Map<String, PluginUiPageState> _pluginUiPages =
      <String, PluginUiPageState>{};
  final Map<String, String> _pluginUiErrors = <String, String>{};
  final Set<String> _pluginUiLoadingPluginIds = <String>{};

  bool _isInitialized = false;
  bool _isRefreshingManifest = false;
  bool _isInstalling = false;
  bool _isExecuting = false;
  double _downloadProgress = 0;
  String? _activePluginId;
  String? _lastError;
  PythonExecutionResult? _lastExecutionResult;
  String? _lastExecutionPluginId;

  Directory? _pluginRootDir;
  Directory? _runtimeWorkDir;

  PluginProvider({
    PluginService? pluginService,
    PythonPluginService? pythonService,
  }) : _pluginService = pluginService ?? PluginService(),
       _pythonService = pythonService ?? PythonPluginService() {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  bool get isInitialized => _isInitialized;
  bool get isRefreshingManifest => _isRefreshingManifest;
  bool get isInstalling => _isInstalling;
  bool get isExecuting => _isExecuting;
  bool get isBusy => _isRefreshingManifest || _isInstalling || _isExecuting;
  double get downloadProgress => _downloadProgress;
  String? get activePluginId => _activePluginId;
  String? get lastError => _lastError;
  PythonExecutionResult? get lastExecutionResult => _lastExecutionResult;
  String? get lastExecutionPluginId => _lastExecutionPluginId;
  PluginManifestV2? get manifest => _manifest;

  /// 读取指定插件当前 UI 页面快照。
  PluginUiPageState? pluginUiPage(String pluginId) => _pluginUiPages[pluginId];

  /// 读取指定插件 UI 错误。
  String? pluginUiError(String pluginId) => _pluginUiErrors[pluginId];

  /// 指定插件 UI 是否正在加载/交互。
  bool isPluginUiLoading(String pluginId) =>
      _pluginUiLoadingPluginIds.contains(pluginId);

  /// 当前插件列表（远端清单 + 本地导入）按名称排序。
  List<PluginDefinition> get plugins {
    final byId = <String, PluginDefinition>{};
    for (final plugin in _manifest?.plugins ?? const <PluginDefinition>[]) {
      byId[plugin.id] = plugin;
    }
    byId.addAll(_localPluginsById);
    final result = byId.values.toList();
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  /// 当前 Hook 执行日志。
  List<PluginHookLogEntry> get hookLogs => PluginHookBus.logs;

  /// 查询插件是否已安装。
  bool isInstalled(String pluginId) => _installedRecords.containsKey(pluginId);

  /// 查询插件是否启用。
  bool isPluginEnabled(String pluginId) {
    final record = _installedRecords[pluginId];
    return record != null && record.enabled;
  }

  /// 查询插件工具是否启用。
  bool isToolEnabled(String pluginId, String toolName) {
    final record = _installedRecords[pluginId];
    if (record == null || !record.enabled) return false;
    return record.enabledTools.contains(toolName);
  }

  /// 查询插件安装状态。
  PluginInstallState stateForPlugin(String pluginId) {
    if (_pluginStates.containsKey(pluginId)) {
      return _pluginStates[pluginId]!;
    }
    return isInstalled(pluginId)
        ? PluginInstallState.ready
        : PluginInstallState.notInstalled;
  }

  /// 根据 ID 获取插件定义。
  PluginDefinition? getPluginById(String pluginId) {
    for (final plugin in plugins) {
      if (plugin.id == pluginId) return plugin;
    }
    return null;
  }

  /// 刷新远端插件清单。
  Future<void> refreshManifest() async {
    if (_pluginRootDir == null) return;
    _isRefreshingManifest = true;
    _lastError = null;
    notifyListeners();
    try {
      final fetched = await _pluginService.fetchManifest(_manifestUrl);
      _manifest = fetched;
      await _reloadLocalPluginsFromDisk();
      await _saveBasicState();
      _syncRegistry();
    } catch (e, st) {
      _lastError = '清单加载失败: $e';
      AppLogger.e('刷新插件清单失败', e, st);
    } finally {
      _isRefreshingManifest = false;
      notifyListeners();
    }
  }

  /// 安装清单插件（自动处理包依赖）。
  Future<void> installPlugin(String pluginId) async {
    if (_isInstalling || _pluginRootDir == null) return;
    final plugin = getPluginById(pluginId);
    if (plugin == null) {
      _lastError = '插件不存在: $pluginId';
      notifyListeners();
      return;
    }

    _isInstalling = true;
    _activePluginId = pluginId;
    _downloadProgress = 0;
    _lastError = null;
    _pluginStates[pluginId] = PluginInstallState.installing;
    notifyListeners();

    final installedPackages = <InstalledPluginPackageRecord>[];
    final visited = <String>{};
    try {
      Future<void> installPackage(PluginPackage package) async {
        if (!visited.add(package.id)) return;
        for (final dependencyId in package.dependencies) {
          final dependency = plugin.packages.where((item) => item.id == dependencyId);
          if (dependency.isEmpty) {
            throw Exception('缺少依赖包: ${package.id} -> $dependencyId');
          }
          await installPackage(dependency.first);
        }

        if (package.url.trim().isNotEmpty) {
          await _pluginService.installPackageFromUrl(
            package: package,
            pluginRootDir: _pluginRootDir!,
            onProgress: (progress) {
              _downloadProgress = progress;
              notifyListeners();
            },
          );
        }

        installedPackages.add(
          InstalledPluginPackageRecord(
            id: package.id,
            version: package.version,
            targetDir: package.targetDir,
            pythonPathEntries: package.pythonPathEntries,
            entryPoint: package.entryPoint,
          ),
        );
      }

      for (final package in plugin.packages) {
        await installPackage(package);
      }

      final enabledTools =
          plugin.tools
              .where((item) => item.enabledByDefault)
              .map((item) => item.name)
              .toList();

      _installedRecords[pluginId] = InstalledPluginRecord(
        pluginId: pluginId,
        pluginVersion: plugin.version,
        enabled: true,
        enabledTools: enabledTools,
        packages: installedPackages,
        installedAt: DateTime.now(),
        isLocalImport: _localPluginsById.containsKey(pluginId),
      );
      _pluginStates[pluginId] = PluginInstallState.ready;
      _downloadProgress = 1;
      await _saveInstalledRecords();
      _syncRegistry();
    } on PluginPackageChecksumException catch (e, st) {
      _pluginStates[pluginId] = PluginInstallState.broken;
      _lastError =
          '校验值错误（${e.packageId}）\n'
          '期望 SHA256: ${e.expectedSha256}\n'
          '实际 SHA256: ${e.actualSha256}';
      AppLogger.e('插件安装校验失败: $pluginId', e, st);
    } catch (e, st) {
      _pluginStates[pluginId] = PluginInstallState.broken;
      _lastError = '插件安装失败: $e';
      AppLogger.e('安装插件失败: $pluginId', e, st);
    } finally {
      _isInstalling = false;
      _activePluginId = null;
      notifyListeners();
    }
  }

  /// 导入本地插件 zip 并安装。
  Future<void> importLocalPlugin() async {
    if (_isInstalling || _pluginRootDir == null) return;
    _isInstalling = true;
    _activePluginId = null;
    _downloadProgress = 0;
    _lastError = null;
    notifyListeners();
    try {
      final payload = await _pluginService.pickAndParseLocalPluginZip();
      if (payload == null) {
        return;
      }
      final plugin = payload.plugin;
      final targetDir = p.join('local_plugins', plugin.id, plugin.version);
      _activePluginId = plugin.id;
      _pluginStates[plugin.id] = PluginInstallState.installing;
      notifyListeners();

      await _pluginService.installPackageFromLocalZip(
        sourceZipPath: payload.sourceZipPath,
        pluginRootDir: _pluginRootDir!,
        targetDir: targetDir,
      );

      _localPluginsById[plugin.id] = plugin;
      final firstPackage =
          plugin.packages.isNotEmpty ? plugin.packages.first : null;
      final enabledTools =
          plugin.tools
              .where((item) => item.enabledByDefault)
              .map((item) => item.name)
              .toList();
      _installedRecords[plugin.id] = InstalledPluginRecord(
        pluginId: plugin.id,
        pluginVersion: plugin.version,
        enabled: true,
        enabledTools: enabledTools,
        packages: <InstalledPluginPackageRecord>[
          InstalledPluginPackageRecord(
            id: firstPackage?.id ?? 'main',
            version: firstPackage?.version ?? plugin.version,
            targetDir: targetDir,
            pythonPathEntries: firstPackage?.pythonPathEntries ?? const <String>['.'],
            entryPoint: firstPackage?.entryPoint,
          ),
        ],
        installedAt: DateTime.now(),
        isLocalImport: true,
      );
      _pluginStates[plugin.id] = PluginInstallState.ready;
      _downloadProgress = 1;
      await _saveInstalledRecords();
      _syncRegistry();
    } catch (e, st) {
      _lastError = '导入本地插件失败: $e';
      AppLogger.e('导入本地插件失败', e, st);
    } finally {
      _isInstalling = false;
      _activePluginId = null;
      notifyListeners();
    }
  }

  /// 卸载插件及其安装包。
  Future<void> uninstallPlugin(String pluginId) async {
    if (_isInstalling || _pluginRootDir == null) return;
    final record = _installedRecords[pluginId];
    if (record == null) return;

    _isInstalling = true;
    _activePluginId = pluginId;
    _downloadProgress = 0;
    _lastError = null;
    notifyListeners();
    try {
      final packages = record.packages.reversed.toList();
      for (final package in packages) {
        await _pluginService.uninstallByRelativeDir(
          pluginRootDir: _pluginRootDir!,
          relativeTargetDir: package.targetDir,
        );
      }
      _installedRecords.remove(pluginId);
      _pluginStates[pluginId] = PluginInstallState.notInstalled;
      // 卸载后清理页面状态，避免残留旧 DSL 渲染结果。
      _pluginUiPages.remove(pluginId);
      _pluginUiErrors.remove(pluginId);
      _pluginUiLoadingPluginIds.remove(pluginId);

      // 若是本地导入插件，且清单中不存在，则同时从列表移除。
      if (_localPluginsById.containsKey(pluginId) &&
          (_manifest?.plugins.any((item) => item.id == pluginId) != true)) {
        _localPluginsById.remove(pluginId);
      }
      await _saveInstalledRecords();
      _syncRegistry();
    } catch (e, st) {
      _lastError = '卸载插件失败: $e';
      _pluginStates[pluginId] = PluginInstallState.broken;
      AppLogger.e('卸载插件失败: $pluginId', e, st);
    } finally {
      _isInstalling = false;
      _activePluginId = null;
      notifyListeners();
    }
  }

  /// 开关插件启用状态。
  Future<void> togglePluginEnabled(String pluginId, bool enabled) async {
    final record = _installedRecords[pluginId];
    if (record == null) return;
    _installedRecords[pluginId] = record.copyWith(enabled: enabled);
    await _saveInstalledRecords();
    _syncRegistry();
    notifyListeners();
  }

  /// 开关插件工具暴露状态。
  Future<void> toggleToolEnabled(
    String pluginId,
    String toolName,
    bool enabled,
  ) async {
    final record = _installedRecords[pluginId];
    if (record == null) return;
    final enabledTools = record.enabledTools.toSet();
    if (enabled) {
      enabledTools.add(toolName);
    } else {
      enabledTools.remove(toolName);
    }
    _installedRecords[pluginId] = record.copyWith(
      enabledTools: enabledTools.toList(),
    );
    await _saveInstalledRecords();
    _syncRegistry();
    notifyListeners();
  }

  /// 加载插件 DSL 页面定义。
  Future<void> loadPluginUiPage({
    required String pluginId,
    Map<String, dynamic>? payload,
  }) async {
    // 非强制能力：未提供 ui/schema.py 时视为“无页面”，不当作错误处理。
    if (!_pluginHasUiSchema(pluginId)) {
      _pluginUiPages.remove(pluginId);
      _pluginUiErrors.remove(pluginId);
      notifyListeners();
      return;
    }
    if (_pluginUiLoadingPluginIds.contains(pluginId)) return;
    _pluginUiLoadingPluginIds.add(pluginId);
    _pluginUiErrors.remove(pluginId);
    notifyListeners();
    try {
      final raw = await PluginRuntimeExecutor.loadPluginUiPage(
        pluginId: pluginId,
        payload: payload ?? const <String, dynamic>{},
      );
      _pluginUiPages[pluginId] = PluginUiPageState.fromJson(raw);
    } catch (e, st) {
      _pluginUiErrors[pluginId] = '加载插件 UI 失败: $e';
      AppLogger.e('加载插件 UI 失败($pluginId)', e, st);
    } finally {
      _pluginUiLoadingPluginIds.remove(pluginId);
      notifyListeners();
    }
  }

  /// 分发组件交互事件，并用 Python 返回的新页面替换当前页面状态。
  Future<String?> dispatchPluginUiEvent({
    required String pluginId,
    required String componentId,
    required String eventType,
    dynamic value,
    Map<String, dynamic>? payload,
  }) async {
    if (!_pluginHasUiSchema(pluginId)) {
      _pluginUiPages.remove(pluginId);
      _pluginUiErrors.remove(pluginId);
      notifyListeners();
      return null;
    }
    if (_pluginUiLoadingPluginIds.contains(pluginId)) return null;
    final current = _pluginUiPages[pluginId];
    if (current == null) {
      await loadPluginUiPage(pluginId: pluginId, payload: payload);
      return null;
    }

    _pluginUiLoadingPluginIds.add(pluginId);
    _pluginUiErrors.remove(pluginId);
    notifyListeners();
    try {
      final raw = await PluginRuntimeExecutor.dispatchPluginUiEvent(
        pluginId: pluginId,
        eventType: eventType,
        componentId: componentId,
        value: value,
        payload: payload ?? const <String, dynamic>{},
        state: current.state,
      );
      final next = PluginUiPageState.fromJson(raw);
      _pluginUiPages[pluginId] = next;
      return next.message;
    } catch (e, st) {
      _pluginUiErrors[pluginId] = '插件 UI 交互失败: $e';
      AppLogger.e('插件 UI 交互失败($pluginId/$componentId/$eventType)', e, st);
      return null;
    } finally {
      _pluginUiLoadingPluginIds.remove(pluginId);
      notifyListeners();
    }
  }

  /// 在插件页执行 Python 代码（用于 Python 类插件调试）。
  Future<void> executePythonCodeForPlugin({
    required String pluginId,
    required String code,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final normalizedCode = code.trim();
    if (normalizedCode.isEmpty || _runtimeWorkDir == null || _isExecuting) return;
    _isExecuting = true;
    _lastError = null;
    _lastExecutionResult = null;
    _lastExecutionPluginId = pluginId;
    notifyListeners();
    try {
      final extraPaths = PluginRegistry.instance.resolvePythonPathsForPlugin(pluginId);
      final result = await _pythonService.executeCode(
        code: normalizedCode,
        timeout: timeout,
        extraSysPaths: extraPaths,
        workingDirectory: _runtimeWorkDir!.path,
      );
      _lastExecutionResult = result;
      if (result.timedOut) {
        _lastError = '执行超时（${timeout.inSeconds} 秒）';
      } else if (!result.isSuccess) {
        _lastError = result.stderr.trim().isEmpty ? '执行失败' : result.stderr.trim();
      }
    } catch (e, st) {
      _lastError = '执行失败: $e';
      AppLogger.e('执行插件 Python 代码失败($pluginId)', e, st);
    } finally {
      _isExecuting = false;
      notifyListeners();
    }
  }

  /// 清空插件执行输出。
  void clearExecutionResult() {
    _lastExecutionResult = null;
    _lastExecutionPluginId = null;
    _lastError = null;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      PluginHookBus.emit('app_resume');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      _pluginRootDir = Directory(
        p.join(supportDir.path, 'plugin_runtime'),
      );
      if (!_pluginRootDir!.existsSync()) {
        await _pluginRootDir!.create(recursive: true);
      }
      _runtimeWorkDir = Directory(
        p.join(_pluginRootDir!.path, 'runtime'),
      );
      if (!_runtimeWorkDir!.existsSync()) {
        await _runtimeWorkDir!.create(recursive: true);
      }

      await _loadBasicState();
      await _loadInstalledRecords();
      await _reloadLocalPluginsFromDisk();
      await refreshManifest();
      _syncRegistry();
      await PluginHookBus.emit('app_start');
    } catch (e, st) {
      _lastError = '插件初始化失败: $e';
      AppLogger.e('初始化插件系统失败', e, st);
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> _loadBasicState() async {
    final prefs = await SharedPreferences.getInstance();
    _manifestUrl = (prefs.getString(_kManifestUrl) ?? defaultManifestUrl).trim();
    if (_manifestUrl.isEmpty) {
      _manifestUrl = defaultManifestUrl;
    }
    _lastError = prefs.getString(_kLastError)?.trim();
  }

  Future<void> _saveBasicState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kManifestUrl, _manifestUrl);
    if ((_lastError ?? '').trim().isEmpty) {
      await prefs.remove(_kLastError);
    } else {
      await prefs.setString(_kLastError, _lastError!.trim());
    }
  }

  Future<void> _loadInstalledRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(recordsStorageKey) ?? '';
    _installedRecords.clear();
    if (raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is! Map) continue;
        final record = InstalledPluginRecord.fromJson(
          Map<String, dynamic>.from(item),
        );
        _installedRecords[record.pluginId] = record;
        _pluginStates[record.pluginId] = PluginInstallState.ready;
      }
    } catch (e, st) {
      AppLogger.e('读取插件安装记录失败', e, st);
    }
  }

  Future<void> _saveInstalledRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = _installedRecords.values.map((item) => item.toJson()).toList();
    await prefs.setString(recordsStorageKey, jsonEncode(payload));
  }

  Future<void> _reloadLocalPluginsFromDisk() async {
    _localPluginsById.clear();
    final root = _pluginRootDir;
    if (root == null) return;
    final localRoot = Directory(p.join(root.path, 'local_plugins'));
    if (!localRoot.existsSync()) return;

    final files = localRoot.listSync(recursive: true, followLinks: false);
    for (final entity in files) {
      if (entity is! File) continue;
      if (p.basename(entity.path).toLowerCase() != 'plugin.json') continue;
      try {
        final raw = await entity.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) continue;
        final plugin = PluginDefinition.fromJson(decoded);
        _localPluginsById[plugin.id] = plugin;
      } catch (e, st) {
        AppLogger.w('忽略无效本地插件定义(${entity.path}): $e');
        AppLogger.e('解析本地插件失败', e, st);
      }
    }
  }

  void _syncRegistry() {
    final root = _pluginRootDir;
    if (root == null) return;
    PluginRegistry.instance.sync(
      pluginRootPath: root.path,
      plugins: plugins,
      installedRecords: _installedRecords,
    );
  }

  bool _pluginHasUiSchema(String pluginId) {
    return PluginRegistry.instance.resolvePluginFilePath(
          pluginId,
          'ui/schema.py',
        ) !=
        null;
  }
}
