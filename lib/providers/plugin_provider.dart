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
  /// 默认远端清单地址；首次启动会使用该地址拉取插件市场。
  static const String defaultManifestUrl =
      'https://raw.githubusercontent.com/CikeSeven/NowChat/main/plugin_manifest.json';

  static const String recordsStorageKey = 'plugin_registry_records_v2';

  /// 基础设置持久化键。
  static const _kManifestUrl = 'plugin_registry_manifest_url_v2';
  static const _kLastError = 'plugin_registry_last_error_v2';
  static const _kGithubMirrorId = 'plugin_registry_github_mirror_id_v1';
  static const _kGithubMirrorCustomBaseUrl =
      'plugin_registry_github_mirror_custom_base_url_v1';

  final PluginService _pluginService;
  final PythonPluginService _pythonService;

  /// 当前生效的清单 URL（可由设置页覆盖）。
  String _manifestUrl = defaultManifestUrl;
  String _githubMirrorId = PluginService.githubMirrorDirect;
  String _githubMirrorCustomBaseUrl = '';
  /// 远端清单（插件市场）快照。
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
  final Map<String, String> _pluginReadmeCache = <String, String>{};

  /// 生命周期状态位：用于控制初始化、下载、执行等互斥行为。
  bool _isInitialized = false;
  bool _isRefreshingManifest = false;
  bool _isInstalling = false;
  bool _isExecuting = false;
  bool _isProbingMirrors = false;
  double _downloadProgress = 0;
  String? _activePluginId;
  String? _lastError;
  PythonExecutionResult? _lastExecutionResult;
  String? _lastExecutionPluginId;
  Map<String, int?> _mirrorProbeLatenciesMs = <String, int?>{};

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
  bool get isProbingMirrors => _isProbingMirrors;
  bool get isBusy => _isRefreshingManifest || _isInstalling || _isExecuting;
  double get downloadProgress => _downloadProgress;
  String? get activePluginId => _activePluginId;
  String? get lastError => _lastError;
  PythonExecutionResult? get lastExecutionResult => _lastExecutionResult;
  String? get lastExecutionPluginId => _lastExecutionPluginId;
  PluginManifestV2? get manifest => _manifest;
  String get githubMirrorId => _githubMirrorId;
  String get githubMirrorCustomBaseUrl => _githubMirrorCustomBaseUrl;
  Map<String, int?> get mirrorProbeLatenciesMs => _mirrorProbeLatenciesMs;
  List<PluginGithubMirrorPreset> get githubMirrorPresets => PluginService.githubMirrorPresets;

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
    AppLogger.i('开始刷新插件清单: url=$_manifestUrl');
    _isRefreshingManifest = true;
    _lastError = null;
    notifyListeners();
    try {
      final fetched = await _pluginService.fetchManifest(
        _manifestUrl,
        mirrorId: _githubMirrorId,
        customMirrorBaseUrl: _githubMirrorCustomBaseUrl,
      );
      _manifest = fetched;
      await _reloadLocalPluginsFromDisk();
      await _saveBasicState();
      _syncRegistry();
      AppLogger.i(
        '插件清单刷新完成: remote=${_manifest?.plugins.length ?? 0}, local=${_localPluginsById.length}',
      );
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
    final missingRequiredPluginIds = _findMissingRequiredPluginIds(plugin);
    if (missingRequiredPluginIds.isNotEmpty) {
      final missingText = _buildRequiredPluginDisplayText(missingRequiredPluginIds);
      _lastError = '请先安装前置插件：$missingText';
      _pluginStates[pluginId] = PluginInstallState.notInstalled;
      AppLogger.w('插件安装被拦截，缺少前置插件: plugin=$pluginId, missing=$missingRequiredPluginIds');
      notifyListeners();
      return;
    }

    _isInstalling = true;
    _activePluginId = pluginId;
    _downloadProgress = 0;
    _lastError = null;
    _pluginStates[pluginId] = PluginInstallState.installing;
    notifyListeners();
    AppLogger.i('开始安装插件: $pluginId');

    try {
      // 新模式：只要声明 repoUrl，就优先按 Git 仓库安装插件。
      // 原因：插件详细元数据与脚本都应以仓库内容为准，避免清单重复维护。
      if (plugin.repoUrl.trim().isNotEmpty) {
        final targetDir = p.join('remote_plugins', plugin.id, plugin.version);
        final installedPluginRaw = await _pluginService.installPluginFromRepo(
          repoUrl: plugin.repoUrl,
          pluginRootDir: _pluginRootDir!,
          targetDir: targetDir,
          mirrorId: _githubMirrorId,
          customMirrorBaseUrl: _githubMirrorCustomBaseUrl,
          onProgress: (progress) {
            _downloadProgress = progress;
            notifyListeners();
          },
        );
        final installedPlugin = installedPluginRaw.copyWith(
          id: plugin.id,
          repoUrl: plugin.repoUrl,
        );
        _localPluginsById[plugin.id] = installedPlugin;
        final firstPackage =
            installedPlugin.packages.isNotEmpty
                ? installedPlugin.packages.first
                : null;
        final enabledTools =
            installedPlugin.tools
                .where((item) => item.enabledByDefault)
                .map((item) => item.name)
                .toList();
        _installedRecords[plugin.id] = InstalledPluginRecord(
          pluginId: plugin.id,
          pluginVersion: installedPlugin.version,
          enabled: true,
          enabledTools: enabledTools,
          packages: <InstalledPluginPackageRecord>[
            InstalledPluginPackageRecord(
              id: firstPackage?.id ?? 'main',
              version: firstPackage?.version ?? installedPlugin.version,
              targetDir: targetDir,
              pythonPathEntries:
                  firstPackage?.pythonPathEntries ?? const <String>['.'],
              entryPoint: firstPackage?.entryPoint,
            ),
          ],
          installedAt: DateTime.now(),
          isLocalImport: false,
        );
        AppLogger.i('插件安装来源: repo(${plugin.repoUrl})');
      } else {
        // 兼容旧模式：清单内直接带 packages 时，按包依赖安装。
        final installedPackages = <InstalledPluginPackageRecord>[];
        final visited = <String>{};
        Future<void> installPackage(PluginPackage package) async {
          if (!visited.add(package.id)) return;
          for (final dependencyId in package.dependencies) {
            final dependency = plugin.packages.where(
              (item) => item.id == dependencyId,
            );
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
        AppLogger.i('插件安装来源: manifest-packages($pluginId)');
      }
      _pluginStates[pluginId] = PluginInstallState.ready;
      _downloadProgress = 1;
      await _saveInstalledRecords();
      _syncRegistry();
      final enabledTools = _installedRecords[pluginId]?.enabledTools ?? const [];
      AppLogger.i(
        '插件安装完成: id=$pluginId, enabledTools=${enabledTools.length}, tools=${enabledTools.join(', ')}',
      );
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
    AppLogger.i('开始导入本地插件');
    try {
      final payload = await _pluginService.pickAndParseLocalPluginZip();
      if (payload == null) {
        AppLogger.i('用户取消本地插件导入');
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
      AppLogger.i('本地插件导入完成: id=${plugin.id}, version=${plugin.version}');
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
    AppLogger.i('开始卸载插件: $pluginId');
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
      _pluginReadmeCache.remove(pluginId);

      // 远端仓库安装的插件，卸载后总是回退到远端清单元数据。
      if (!record.isLocalImport) {
        _localPluginsById.remove(pluginId);
      } else if (_localPluginsById.containsKey(pluginId) &&
          (_manifest?.plugins.any((item) => item.id == pluginId) != true)) {
        // 本地导入插件且清单中不存在时，卸载后从列表移除。
        _localPluginsById.remove(pluginId);
      }
      await _saveInstalledRecords();
      _syncRegistry();
      AppLogger.i('插件卸载完成: $pluginId');
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
    AppLogger.i('插件状态已更新: $pluginId -> ${enabled ? "运行中" : "已暂停"}');
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
    AppLogger.i(
      '工具状态已更新: plugin=$pluginId, tool=$toolName -> ${enabled ? "启用" : "禁用"}',
    );
    notifyListeners();
  }

  /// 加载插件 DSL 页面定义。
  ///
  /// UI 脚本不存在时会静默视为“该插件无配置页”。
  Future<void> loadPluginUiPage({
    required String pluginId,
    Map<String, dynamic>? payload,
  }) async {
    // 非强制能力：未提供 `${pythonNamespace}/schema.py` 时视为“无页面”。
    if (!_pluginHasUiSchema(pluginId)) {
      _pluginUiPages.remove(pluginId);
      _pluginUiErrors.remove(pluginId);
      notifyListeners();
      return;
    }
    if (_pluginUiLoadingPluginIds.contains(pluginId)) return;
    AppLogger.i('开始加载插件配置页面: $pluginId');
    _pluginUiLoadingPluginIds.add(pluginId);
    _pluginUiErrors.remove(pluginId);
    notifyListeners();
    try {
      final raw = await PluginRuntimeExecutor.loadPluginUiPage(
        pluginId: pluginId,
        payload: payload ?? const <String, dynamic>{},
      );
      _pluginUiPages[pluginId] = PluginUiPageState.fromJson(raw);
      AppLogger.i('插件配置页面加载完成: $pluginId');
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
      AppLogger.i('插件 UI 事件已处理: plugin=$pluginId, component=$componentId, event=$eventType');
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
  ///
  /// 该入口面向插件调试，不会影响聊天主链路。
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
        logContext: 'plugin:$pluginId/debug',
        workingDirectory: _runtimeWorkDir!.path,
      );
      _lastExecutionResult = result;
      AppLogger.i(
        '插件 Python 执行完成: plugin=$pluginId, exit=${result.exitCode}, timeout=${result.timedOut}',
      );
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

  /// 读取插件 README 文本：优先本地已安装文件，其次远端仓库。
  ///
  /// 读取成功后会写入内存缓存，减少重复网络请求。
  Future<String> loadPluginReadme(String pluginId) async {
    final cached = _pluginReadmeCache[pluginId];
    if (cached != null && cached.trim().isNotEmpty) {
      return cached;
    }
    final plugin = getPluginById(pluginId);
    if (plugin == null) {
      throw Exception('插件不存在: $pluginId');
    }

    final localReadmePath =
        PluginRegistry.instance.resolvePluginFilePath(pluginId, 'README.md') ??
        PluginRegistry.instance.resolvePluginFilePath(pluginId, 'readme.md');
    if (localReadmePath != null && localReadmePath.trim().isNotEmpty) {
      final content = await File(localReadmePath).readAsString();
      _pluginReadmeCache[pluginId] = content;
      return content;
    }

    if (plugin.repoUrl.trim().isEmpty) {
      throw Exception('插件未提供仓库链接');
    }
    final content = await _pluginService.fetchReadmeFromRepo(
      plugin.repoUrl,
      mirrorId: _githubMirrorId,
      customMirrorBaseUrl: _githubMirrorCustomBaseUrl,
    );
    _pluginReadmeCache[pluginId] = content;
    return content;
  }

  /// 更新当前 GitHub 镜像配置并按需刷新清单。
  Future<void> setGithubMirrorConfig({
    required String mirrorId,
    String? customMirrorBaseUrl,
    bool refreshManifestAfterChange = true,
  }) async {
    final normalizedId = mirrorId.trim();
    final isValid = PluginService.githubMirrorPresets.any((item) => item.id == normalizedId);
    if (!isValid) return;
    final normalizedCustomBase = PluginService.normalizeCustomMirrorBaseUrl(
      customMirrorBaseUrl ?? _githubMirrorCustomBaseUrl,
    );
    final shouldUseCustom = normalizedId == PluginService.githubMirrorCustom;
    if (shouldUseCustom && normalizedCustomBase.isEmpty) {
      _lastError = '自定义代理地址无效';
      notifyListeners();
      return;
    }
    final changed =
        _githubMirrorId != normalizedId ||
        _githubMirrorCustomBaseUrl != normalizedCustomBase;
    if (!changed) {
      if (refreshManifestAfterChange) {
        await refreshManifest();
      }
      return;
    }
    _githubMirrorId = normalizedId;
    _githubMirrorCustomBaseUrl = normalizedCustomBase;
    await _saveBasicState();
    notifyListeners();
    if (refreshManifestAfterChange) {
      await refreshManifest();
    }
  }

  /// 批量测速所有预设镜像，供镜像选择弹窗显示。
  Future<void> probeGithubMirrors() async {
    if (_isProbingMirrors) return;
    _isProbingMirrors = true;
    notifyListeners();
    final result = <String, int?>{};
    try {
      for (final preset in PluginService.githubMirrorPresets) {
        final latency = await _pluginService.probeMirrorLatency(
          mirrorId: preset.id,
          customMirrorBaseUrl: _githubMirrorCustomBaseUrl,
        );
        result[preset.id] = latency;
      }
    } finally {
      _mirrorProbeLatenciesMs = result;
      _isProbingMirrors = false;
      notifyListeners();
    }
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
      AppLogger.i(
        '插件目录初始化完成: root=${_pluginRootDir!.path}, runtime=${_runtimeWorkDir!.path}',
      );

      await _loadBasicState();
      await _loadInstalledRecords();
      await _reloadLocalPluginsFromDisk();
      _syncRegistry();
      await PluginHookBus.emit('app_start');
      AppLogger.i('插件系统初始化完成');

      // 启动阶段仅保证“本地已安装插件”可用，远端清单改为后台异步刷新，
      // 避免首页加载被网络请求阻塞。
      _isInitialized = true;
      notifyListeners();
      unawaited(_refreshManifestInBackground());
    } catch (e, st) {
      _lastError = '插件初始化失败: $e';
      AppLogger.e('初始化插件系统失败', e, st);
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// 在应用进入主页后后台刷新远端清单，不阻塞启动流程。
  Future<void> _refreshManifestInBackground() async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await refreshManifest();
    } catch (e, st) {
      AppLogger.e('后台刷新插件清单失败', e, st);
    }
  }

  /// 恢复清单地址、镜像配置与最近错误等基础状态。
  Future<void> _loadBasicState() async {
    final prefs = await SharedPreferences.getInstance();
    _manifestUrl = (prefs.getString(_kManifestUrl) ?? defaultManifestUrl).trim();
    if (_manifestUrl.isEmpty) {
      _manifestUrl = defaultManifestUrl;
    }
    _lastError = prefs.getString(_kLastError)?.trim();
    final persistedMirrorId = (prefs.getString(_kGithubMirrorId) ?? PluginService.githubMirrorDirect).trim();
    final hasPreset = PluginService.githubMirrorPresets.any((item) => item.id == persistedMirrorId);
    _githubMirrorId = hasPreset ? persistedMirrorId : PluginService.githubMirrorDirect;
    _githubMirrorCustomBaseUrl = PluginService.normalizeCustomMirrorBaseUrl(
      prefs.getString(_kGithubMirrorCustomBaseUrl) ?? '',
    );
  }

  /// 持久化基础状态，供下次启动恢复。
  Future<void> _saveBasicState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kManifestUrl, _manifestUrl);
    await prefs.setString(_kGithubMirrorId, _githubMirrorId);
    if (_githubMirrorCustomBaseUrl.trim().isEmpty) {
      await prefs.remove(_kGithubMirrorCustomBaseUrl);
    } else {
      await prefs.setString(_kGithubMirrorCustomBaseUrl, _githubMirrorCustomBaseUrl);
    }
    if ((_lastError ?? '').trim().isEmpty) {
      await prefs.remove(_kLastError);
    } else {
      await prefs.setString(_kLastError, _lastError!.trim());
    }
  }

  /// 读取已安装插件记录。
  ///
  /// 该记录是运行时真值来源，决定插件是否“已安装/已启用”。
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
      AppLogger.i('已加载插件安装记录: ${_installedRecords.length}');
    } catch (e, st) {
      AppLogger.e('读取插件安装记录失败', e, st);
    }
  }

  Future<void> _saveInstalledRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = _installedRecords.values.map((item) => item.toJson()).toList();
    await prefs.setString(recordsStorageKey, jsonEncode(payload));
  }

  /// 扫描插件目录，恢复本地可解析的 plugin.json。
  Future<void> _reloadLocalPluginsFromDisk() async {
    _localPluginsById.clear();
    final root = _pluginRootDir;
    if (root == null) return;
    if (!root.existsSync()) {
      await root.create(recursive: true);
      return;
    }

    List<FileSystemEntity> files;
    try {
      files = root.listSync(recursive: true, followLinks: false);
    } on FileSystemException catch (e) {
      AppLogger.w('扫描插件目录失败，已跳过本次本地插件重载: $e');
      return;
    }

    for (final entity in files) {
      if (entity is! File) continue;
      if (p.basename(entity.path).toLowerCase() != 'plugin.json') continue;
      try {
        final raw = await entity.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) continue;
        final plugin = PluginDefinition.fromJson(decoded);

        // 已安装插件优先按“安装记录 pluginId”入表，保证列表展示使用本地已安装信息。
        final installedPluginId = _resolveInstalledPluginIdByPluginJsonPath(
          pluginJsonPath: entity.path,
        );
        if (installedPluginId != null && installedPluginId.trim().isNotEmpty) {
          final manifestRepoUrl =
              _manifest?.plugins
                  .where((item) => item.id == installedPluginId)
                  .map((item) => item.repoUrl)
                  .firstWhere(
                    (item) => item.trim().isNotEmpty,
                    orElse: () => plugin.repoUrl,
                  ) ??
              plugin.repoUrl;
          _localPluginsById[installedPluginId] = plugin.copyWith(
            id: installedPluginId,
            repoUrl: manifestRepoUrl,
          );
          continue;
        }

        _localPluginsById[plugin.id] = plugin;
      } catch (e, st) {
        AppLogger.w('忽略无效本地插件定义(${entity.path}): $e');
        AppLogger.e('解析本地插件失败', e, st);
      }
    }
    AppLogger.i('本地插件扫描完成: ${_localPluginsById.length}');
  }

  /// 根据 plugin.json 所在路径反查其对应的安装记录 pluginId。
  ///
  /// 这样即使仓库内 `plugin.json` 的 id 与清单 id 不同，
  /// 也能保证“已安装插件”在 UI 中按安装记录 ID 覆盖展示。
  String? _resolveInstalledPluginIdByPluginJsonPath({
    required String pluginJsonPath,
  }) {
    final root = _pluginRootDir;
    if (root == null) return null;
    final normalizedPluginJsonPath = p.normalize(pluginJsonPath);
    for (final entry in _installedRecords.entries) {
      final pluginId = entry.key;
      final record = entry.value;
      for (final pkg in record.packages) {
        final pkgRoot = p.normalize(p.join(root.path, pkg.targetDir));
        if (normalizedPluginJsonPath.startsWith(pkgRoot)) {
          return pluginId;
        }
      }
    }
    return null;
  }

  /// 将 Provider 状态同步到运行时注册表。
  ///
  /// 任何安装/卸载/启停/清单更新后都必须调用，确保工具与 Hook 视图一致。
  void _syncRegistry() {
    final root = _pluginRootDir;
    if (root == null) return;
    PluginRegistry.instance.sync(
      pluginRootPath: root.path,
      plugins: plugins,
      installedRecords: _installedRecords,
    );
    AppLogger.i(
      '插件注册表已同步: plugins=${plugins.length}, installed=${_installedRecords.length}',
    );
  }

  /// 检查插件是否提供 UI DSL 入口文件。
  bool _pluginHasUiSchema(String pluginId) {
    final plugin = getPluginById(pluginId);
    if (plugin == null) return false;
    if (plugin.type == 'python' && plugin.pythonNamespace.trim().isEmpty) {
      return false;
    }
    final relativePath =
        plugin.type == 'python'
            ? '${plugin.pythonNamespace.trim()}/schema.py'
            : 'ui/schema.py';
    return PluginRegistry.instance.resolvePluginFilePath(
          pluginId,
          relativePath,
        ) !=
        null;
  }

  /// 查询指定插件缺失的前置插件 ID 列表。
  ///
  /// 该方法用于 UI 层在“安装前”做显式提示，避免用户点击后无感失败。
  List<String> missingRequiredPluginIdsFor(String pluginId) {
    final plugin = getPluginById(pluginId);
    if (plugin == null) return const <String>[];
    return _findMissingRequiredPluginIds(plugin);
  }

  /// 返回插件展示标签：优先“名称(id)”，回退为 id。
  String pluginDisplayLabel(String pluginId) {
    final plugin = getPluginById(pluginId);
    if (plugin == null) return pluginId;
    final name = plugin.name.trim();
    if (name.isEmpty) return pluginId;
    return '$name($pluginId)';
  }

  /// 返回当前插件缺失的前置插件 ID 列表。
  ///
  /// 仅检查“已安装”状态，不强制要求前置插件处于启用状态。
  List<String> _findMissingRequiredPluginIds(PluginDefinition plugin) {
    final requiredIds = plugin.requiredPluginIds.toSet();
    requiredIds.removeWhere((item) => item == plugin.id);
    if (requiredIds.isEmpty) return const <String>[];
    return requiredIds.where((item) => !isInstalled(item)).toList();
  }

  /// 将前置插件 ID 列表格式化为可读提示文本。
  ///
  /// 若能解析到插件名称，则按“名称(id)”展示；否则仅展示 ID。
  String _buildRequiredPluginDisplayText(List<String> pluginIds) {
    if (pluginIds.isEmpty) return '';
    final labels = pluginIds.map((pluginId) {
      final plugin = getPluginById(pluginId);
      final name = (plugin?.name ?? '').trim();
      if (name.isEmpty) return pluginId;
      return '$name($pluginId)';
    }).toList();
    return labels.join('、');
  }
}
