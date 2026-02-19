/// 通用插件包定义：一个插件可包含多个可下载包。
class PluginPackage {
  final String id;
  final String name;
  final String description;
  final String version;
  final String url;
  final String sha256;
  final int? sizeBytes;
  final String targetDir;
  final List<String> pythonPathEntries;
  final String? entryPoint;
  final List<String> dependencies;

  const PluginPackage({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.url,
    required this.sha256,
    required this.targetDir,
    required this.pythonPathEntries,
    required this.dependencies,
    this.entryPoint,
    this.sizeBytes,
  });

  factory PluginPackage.fromJson(
    Map<String, dynamic> json, {
    required String context,
    bool requireDownloadFields = true,
  }) {
    final id = (json['id'] ?? '').toString().trim();
    final name = (json['name'] ?? '').toString().trim();
    final description = (json['description'] ?? '').toString().trim();
    final version = (json['version'] ?? '').toString().trim();
    final url = (json['url'] ?? '').toString().trim();
    final sha256 = (json['sha256'] ?? '').toString().trim().toLowerCase();
    final targetDir = (json['targetDir'] ?? '').toString().trim();
    final entryPointRaw = (json['entryPoint'] ?? '').toString().trim();
    final rawDependencies = json['dependencies'];
    final rawPythonPathEntries = json['pythonPathEntries'];
    final pythonPathEntries =
        rawPythonPathEntries is List
            ? rawPythonPathEntries
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty)
                .toList()
            : const <String>[];
    final dependencies =
        rawDependencies is List
            ? rawDependencies
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty)
                .toList()
            : const <String>[];

    final missingFields = <String>[];
    if (id.isEmpty) missingFields.add('id');
    if (name.isEmpty) missingFields.add('name');
    if (version.isEmpty) missingFields.add('version');
    if (targetDir.isEmpty) missingFields.add('targetDir');
    if (requireDownloadFields) {
      if (url.isEmpty) missingFields.add('url');
      if (sha256.isEmpty) missingFields.add('sha256');
    }
    if (missingFields.isNotEmpty) {
      throw FormatException(
        '插件包字段不完整($context): ${missingFields.join(', ')}',
      );
    }

    return PluginPackage(
      id: id,
      name: name,
      description: description,
      version: version,
      url: url,
      sha256: sha256,
      sizeBytes:
          json['sizeBytes'] is num ? (json['sizeBytes'] as num).toInt() : null,
      targetDir: targetDir,
      pythonPathEntries:
          pythonPathEntries.isEmpty ? const <String>['.'] : pythonPathEntries,
      dependencies: dependencies,
      entryPoint: entryPointRaw.isEmpty ? null : entryPointRaw,
    );
  }
}

/// 插件工具定义：会映射为模型可调用的 function tool。
class PluginToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parametersSchema;
  final String runtime;
  final String? scriptPath;
  final String? inlineCode;
  final int timeoutSec;
  final int outputLimit;
  final bool enabledByDefault;

  const PluginToolDefinition({
    required this.name,
    required this.description,
    required this.parametersSchema,
    required this.runtime,
    required this.timeoutSec,
    required this.outputLimit,
    required this.enabledByDefault,
    this.scriptPath,
    this.inlineCode,
  });

  factory PluginToolDefinition.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] ?? '').toString().trim();
    final description = (json['description'] ?? '').toString().trim();
    final runtime = (json['runtime'] ?? '').toString().trim();
    final scriptPath = (json['scriptPath'] ?? '').toString().trim();
    final inlineCode = (json['inlineCode'] ?? '').toString();
    final parameters = json['parameters'];

    if (name.isEmpty || runtime.isEmpty) {
      throw const FormatException('工具字段不完整(name/runtime)');
    }
    if (parameters is! Map<String, dynamic>) {
      throw FormatException('工具参数格式错误($name)');
    }

    return PluginToolDefinition(
      name: name,
      description: description,
      parametersSchema: parameters,
      runtime: runtime,
      scriptPath: scriptPath.isEmpty ? null : scriptPath,
      inlineCode: inlineCode.trim().isEmpty ? null : inlineCode,
      timeoutSec:
          json['timeoutSec'] is num
              ? (json['timeoutSec'] as num).toInt()
              : 20,
      outputLimit:
          json['outputLimit'] is num
              ? (json['outputLimit'] as num).toInt()
              : 12000,
      enabledByDefault: json['enabledByDefault'] != false,
    );
  }
}

/// 插件 Hook 定义：声明事件与处理方式。
class PluginHookDefinition {
  final String event;
  final String runtime;
  final String? scriptPath;
  final String? inlineCode;
  final int priority;

  const PluginHookDefinition({
    required this.event,
    required this.runtime,
    required this.priority,
    this.scriptPath,
    this.inlineCode,
  });

  factory PluginHookDefinition.fromJson(Map<String, dynamic> json) {
    final event = (json['event'] ?? '').toString().trim();
    final runtime = (json['runtime'] ?? '').toString().trim();
    final scriptPath = (json['scriptPath'] ?? '').toString().trim();
    final inlineCode = (json['inlineCode'] ?? '').toString();
    if (event.isEmpty || runtime.isEmpty) {
      throw const FormatException('Hook 字段不完整(event/runtime)');
    }
    return PluginHookDefinition(
      event: event,
      runtime: runtime,
      priority: json['priority'] is num ? (json['priority'] as num).toInt() : 0,
      scriptPath: scriptPath.isEmpty ? null : scriptPath,
      inlineCode: inlineCode.trim().isEmpty ? null : inlineCode,
    );
  }
}

/// 插件定义：包含包、工具、Hook 与权限声明。
class PluginDefinition {
  final String id;
  final String name;
  final String author;
  final String description;
  final String version;
  final String type;
  final List<PluginPackage> packages;
  final List<PluginToolDefinition> tools;
  final List<PluginHookDefinition> hooks;
  final List<String> permissions;

  const PluginDefinition({
    required this.id,
    required this.name,
    required this.author,
    required this.description,
    required this.version,
    required this.type,
    required this.packages,
    required this.tools,
    required this.hooks,
    required this.permissions,
  });

  factory PluginDefinition.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString().trim();
    final name = (json['name'] ?? '').toString().trim();
    // 兼容旧插件配置，未填写作者时回退默认值，避免历史插件导入失败。
    final authorRaw = (json['author'] ?? '').toString().trim();
    final author = authorRaw.isEmpty ? 'Unknown' : authorRaw;
    final version = (json['version'] ?? '').toString().trim();
    final description = (json['description'] ?? '').toString().trim();
    final type = (json['type'] ?? '').toString().trim();
    if (id.isEmpty || name.isEmpty || version.isEmpty || type.isEmpty) {
      throw const FormatException('插件字段不完整(id/name/version/type)');
    }

    final rawPackages = json['packages'];
    final packages =
        rawPackages is List
            ? rawPackages.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                if (item is! Map) {
                  throw FormatException('插件包格式错误($id#$index)');
                }
                final itemMap = Map<String, dynamic>.from(item);
                final hasDownloadFields =
                    (itemMap['url'] ?? '').toString().trim().isNotEmpty ||
                        (itemMap['sha256'] ?? '').toString().trim().isNotEmpty;
                return PluginPackage.fromJson(
                  itemMap,
                  context: '$id#$index',
                  requireDownloadFields: hasDownloadFields,
                );
              }).toList()
            : _legacyPackages(id, json);

    final rawTools = json['tools'];
    final tools =
        rawTools is List
            ? rawTools
                .whereType<Map>()
                .map((item) => PluginToolDefinition.fromJson(Map<String, dynamic>.from(item)))
                .toList()
            : const <PluginToolDefinition>[];

    final rawHooks = json['hooks'];
    final hooks =
        rawHooks is List
            ? rawHooks
                .whereType<Map>()
                .map((item) => PluginHookDefinition.fromJson(Map<String, dynamic>.from(item)))
                .toList()
            : const <PluginHookDefinition>[];

    final rawPermissions = json['permissions'];
    final permissions =
        rawPermissions is List
            ? rawPermissions
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty)
                .toList()
            : const <String>[];

    return PluginDefinition(
      id: id,
      name: name,
      author: author,
      description: description,
      version: version,
      type: type,
      packages: packages,
      tools: tools,
      hooks: hooks,
      permissions: permissions,
    );
  }

  /// 兼容旧清单：将 core + libraries 映射为 packages。
  static List<PluginPackage> _legacyPackages(
    String pluginId,
    Map<String, dynamic> json,
  ) {
    final result = <PluginPackage>[];
    final rawCore = json['core'];
    if (rawCore is Map) {
      result.add(
        PluginPackage.fromJson(
          Map<String, dynamic>.from(rawCore),
          context: '$pluginId#core',
          requireDownloadFields: false,
        ),
      );
    }
    final rawLibraries = json['libraries'];
    if (rawLibraries is List) {
      for (var i = 0; i < rawLibraries.length; i += 1) {
        final item = rawLibraries[i];
        if (item is! Map) continue;
        result.add(
          PluginPackage.fromJson(
            Map<String, dynamic>.from(item),
            context: '$pluginId#libraries[$i]',
          ),
        );
      }
    }
    return result;
  }
}

/// 插件清单 v2：支持多插件并行分发。
class PluginManifestV2 {
  final int manifestVersion;
  final List<PluginDefinition> plugins;

  const PluginManifestV2({
    required this.manifestVersion,
    required this.plugins,
  });

  factory PluginManifestV2.fromJson(Map<String, dynamic> json) {
    final manifestVersion =
        json['manifestVersion'] is num
            ? (json['manifestVersion'] as num).toInt()
            : 1;
    final rawPlugins = json['plugins'];
    if (rawPlugins is! List) {
      throw const FormatException('清单缺少 plugins 列表');
    }
    final plugins = rawPlugins.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      if (item is! Map) {
        throw FormatException('插件定义格式错误(index=$index)');
      }
      return PluginDefinition.fromJson(Map<String, dynamic>.from(item));
    }).toList();

    return PluginManifestV2(
      manifestVersion: manifestVersion,
      plugins: plugins,
    );
  }
}
