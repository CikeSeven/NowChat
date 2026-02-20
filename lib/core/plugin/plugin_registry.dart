import 'dart:io';

import 'package:now_chat/core/models/plugin_install_record.dart';
import 'package:now_chat/core/models/plugin_manifest_v2.dart';
import 'package:now_chat/util/app_logger.dart';
import 'package:path/path.dart' as p;

/// 已启用工具绑定信息，用于工具 schema 生成与执行路由。
class EnabledPluginToolBinding {
  final PluginDefinition plugin;
  final PluginToolDefinition tool;

  const EnabledPluginToolBinding({required this.plugin, required this.tool});
}

/// 插件注册表：维护运行时可见的插件、安装记录与工具映射。
///
/// 该类只做“读模型 + 计算映射”，不直接负责网络或磁盘 IO。
/// 这样可以保证工具执行链路在高频调用时只依赖内存数据。
class PluginRegistry {
  PluginRegistry._();

  static final PluginRegistry instance = PluginRegistry._();

  String? _pluginRootPath;
  final Map<String, PluginDefinition> _pluginsById =
      <String, PluginDefinition>{};
  final Map<String, InstalledPluginRecord> _recordsByPluginId =
      <String, InstalledPluginRecord>{};

  /// 同步当前清单与安装记录到运行时内存。
  ///
  /// 通常在以下时机调用：
  /// 1. 启动加载本地插件后。
  /// 2. 插件安装/卸载/启停后。
  /// 3. 远端清单刷新并重建视图模型后。
  void sync({
    required String pluginRootPath,
    required List<PluginDefinition> plugins,
    required Map<String, InstalledPluginRecord> installedRecords,
  }) {
    _pluginRootPath = pluginRootPath;
    _pluginsById
      ..clear()
      ..addEntries(plugins.map((item) => MapEntry(item.id, item)));
    _recordsByPluginId
      ..clear()
      ..addAll(installedRecords);

    // 这里主动打印汇总日志，便于定位“为什么工具未出现在模型 schema 中”。
    final enabledPluginCount =
        _recordsByPluginId.values.where((item) => item.enabled).length;
    final enabledTools = resolveEnabledTools();
    AppLogger.i(
      'PluginRegistry 同步完成: plugins=${_pluginsById.length}, installed=${_recordsByPluginId.length}, enabledPlugins=$enabledPluginCount, enabledTools=${enabledTools.length}',
    );
    if (enabledTools.isNotEmpty) {
      final preview = enabledTools
          .take(20)
          .map((item) => '${item.plugin.id}/${item.tool.name}')
          .join(', ');
      final suffix = enabledTools.length > 20 ? ' ...' : '';
      AppLogger.i('已加载工具: $preview$suffix');
    }
  }

  /// 当前注册表是否已完成初始化同步。
  bool get isReady => _pluginRootPath != null;

  /// 插件运行时根目录（位于应用 files 下）。
  ///
  /// 仅用于构建宿主侧工作目录，不暴露给不受信任代码。
  String? get pluginRootPath => _pluginRootPath;

  /// 返回当前所有插件定义。
  List<PluginDefinition> get plugins => _pluginsById.values.toList();

  /// 根据插件 ID 获取插件定义。
  PluginDefinition? pluginById(String pluginId) => _pluginsById[pluginId];

  /// 根据插件 ID 获取安装记录。
  InstalledPluginRecord? recordByPluginId(String pluginId) =>
      _recordsByPluginId[pluginId];

  /// 是否已安装指定插件。
  bool isPluginInstalled(String pluginId) =>
      _recordsByPluginId.containsKey(pluginId);

  /// 插件是否启用。
  bool isPluginEnabled(String pluginId) {
    final record = _recordsByPluginId[pluginId];
    return record != null && record.enabled;
  }

  /// 指定工具是否启用。
  bool isToolEnabled(String pluginId, String toolName) {
    final record = _recordsByPluginId[pluginId];
    if (record == null || !record.enabled) return false;
    return record.enabledTools.contains(toolName);
  }

  /// 解析所有可用工具（插件启用 + 工具启用）。
  List<EnabledPluginToolBinding> resolveEnabledTools() {
    final result = <EnabledPluginToolBinding>[];
    for (final plugin in _pluginsById.values) {
      final record = _recordsByPluginId[plugin.id];
      if (record == null || !record.enabled) continue;
      for (final tool in plugin.tools) {
        if (!record.enabledTools.contains(tool.name)) continue;
        result.add(EnabledPluginToolBinding(plugin: plugin, tool: tool));
      }
    }
    return result;
  }

  /// 按工具名解析对应插件工具。
  ///
  /// 说明：当前以线性扫描实现，工具规模较小时可读性更高；
  /// 若后续工具量显著增长，可在 `sync` 阶段建立 name->binding 索引。
  EnabledPluginToolBinding? resolveToolByName(String toolName) {
    for (final binding in resolveEnabledTools()) {
      if (binding.tool.name == toolName) return binding;
    }
    return null;
  }

  /// 按事件名解析已启用插件中的 Hook，按优先级降序返回。
  List<(PluginDefinition, PluginHookDefinition)> resolveHooksByEvent(
    String event,
  ) {
    final result = <(PluginDefinition, PluginHookDefinition)>[];
    for (final plugin in _pluginsById.values) {
      final record = _recordsByPluginId[plugin.id];
      if (record == null || !record.enabled) continue;
      for (final hook in plugin.hooks) {
        if (hook.event != event) continue;
        result.add((plugin, hook));
      }
    }
    result.sort((a, b) => b.$2.priority.compareTo(a.$2.priority));
    return result;
  }

  /// 解析插件 Python 路径（含常见原生库目录）。
  ///
  /// 路径顺序约定：
  /// 1. 当前插件自身路径（优先，便于私有依赖覆盖）。
  /// 2. 全局路径提供者插件（`providesGlobalPythonPaths=true`）。
  ///
  /// 该顺序直接影响 Python import 解析结果，不可随意调整。
  List<String> resolvePythonPathsForPlugin(String pluginId) {
    final root = _pluginRootPath;
    if (root == null) return const <String>[];

    final output = <String>[];
    final seen = <String>{};
    final requestedRecord = _recordsByPluginId[pluginId];
    if (requestedRecord == null) return const <String>[];

    // 先追加当前插件自身路径，确保私有路径优先于全局共享路径。
    _appendPythonPathsFromRecord(
      rootPath: root,
      record: requestedRecord,
      output: output,
      seen: seen,
    );

    // 再追加所有“全局 Python 库提供者”插件路径。
    for (final entry in _recordsByPluginId.entries) {
      if (entry.key == pluginId) continue;
      final providerDef = _pluginsById[entry.key];
      if (providerDef == null || !providerDef.providesGlobalPythonPaths) {
        continue;
      }
      if (!entry.value.enabled) continue;
      _appendPythonPathsFromRecord(
        rootPath: root,
        record: entry.value,
        output: output,
        seen: seen,
      );
    }
    return output;
  }

  /// 追加指定安装记录对应的 Python 路径与常见原生库目录。
  ///
  /// `seen` 用于跨 package 去重，避免重复 sys.path 降低 import 性能。
  void _appendPythonPathsFromRecord({
    required String rootPath,
    required InstalledPluginRecord record,
    required List<String> output,
    required Set<String> seen,
  }) {
    for (final pkg in record.packages) {
      final baseDir = p.normalize(p.join(rootPath, pkg.targetDir));
      for (final relativeEntry in pkg.pythonPathEntries) {
        final path = p.normalize(p.join(baseDir, relativeEntry));
        if (seen.add(path)) {
          output.add(path);
        }
      }

      // 常见 native 库目录候选：覆盖 chaquopy 与手工打包两类结构。
      final nativeCandidates = <String>[
        p.normalize(p.join(baseDir, 'chaquopy', 'lib')),
        p.normalize(p.join(baseDir, 'lib')),
        p.normalize(p.join(baseDir, 'libs')),
      ];
      for (final candidate in nativeCandidates) {
        if (!Directory(candidate).existsSync()) continue;
        if (seen.add(candidate)) {
          output.add(candidate);
        }
      }
    }
  }

  /// 将插件内相对文件路径解析为本地可执行绝对路径。
  ///
  /// 安全约束：只接受规范化后的相对路径，过滤 `..`，避免目录穿越。
  String? resolvePluginFilePath(String pluginId, String relativePath) {
    final root = _pluginRootPath;
    final record = _recordsByPluginId[pluginId];
    if (root == null || record == null) return null;
    final normalizedRelative = _normalizeRelativePath(relativePath);
    if (normalizedRelative.isEmpty) return null;

    for (final pkg in record.packages) {
      final candidate = p.normalize(
        p.join(root, pkg.targetDir, normalizedRelative),
      );
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  String _normalizeRelativePath(String raw) {
    // 过滤空段与 `..`，阻断通过脚本路径访问插件目录外文件。
    final normalized = raw.replaceAll('\\', '/');
    final parts =
        normalized
            .split('/')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty && item != '.' && item != '..')
            .toList();
    return p.joinAll(parts);
  }
}
