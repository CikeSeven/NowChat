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
  final String repoUrl;
  final String author;
  final String description;
  final String version;
  final String type;
  /// Python 插件的 UI 命名空间目录（例如 `sample_tool_ui`）。
  ///
  /// 运行时会按 `${pythonNamespace}/schema.py` 查找插件配置页入口，
  /// 用于避免多个插件共用 `ui` 包名导致的导入冲突。
  final String pythonNamespace;
  /// 是否将本插件的 Python 路径暴露为“全局共享路径”。
  ///
  /// 启用后，其他插件执行 Python 代码时也会自动追加这些路径，
  /// 适合“基础库插件”场景（例如统一提供 numpy/pandas）。
  final bool providesGlobalPythonPaths;
  final List<PluginPackage> packages;
  final List<PluginToolDefinition> tools;
  final List<PluginHookDefinition> hooks;
  final List<String> permissions;

  const PluginDefinition({
    required this.id,
    required this.name,
    required this.repoUrl,
    required this.author,
    required this.description,
    required this.version,
    required this.type,
    required this.pythonNamespace,
    required this.providesGlobalPythonPaths,
    required this.packages,
    required this.tools,
    required this.hooks,
    required this.permissions,
  });

  /// 返回新对象，用于在“清单最小字段 + 仓库 plugin.json”之间做字段合并。
  PluginDefinition copyWith({
    String? id,
    String? name,
    String? repoUrl,
    String? author,
    String? description,
    String? version,
    String? type,
    String? pythonNamespace,
    bool? providesGlobalPythonPaths,
    List<PluginPackage>? packages,
    List<PluginToolDefinition>? tools,
    List<PluginHookDefinition>? hooks,
    List<String>? permissions,
  }) {
    return PluginDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      repoUrl: repoUrl ?? this.repoUrl,
      author: author ?? this.author,
      description: description ?? this.description,
      version: version ?? this.version,
      type: type ?? this.type,
      pythonNamespace: pythonNamespace ?? this.pythonNamespace,
      providesGlobalPythonPaths:
          providesGlobalPythonPaths ?? this.providesGlobalPythonPaths,
      packages: packages ?? this.packages,
      tools: tools ?? this.tools,
      hooks: hooks ?? this.hooks,
      permissions: permissions ?? this.permissions,
    );
  }

  factory PluginDefinition.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString().trim();
    final nameRaw = (json['name'] ?? '').toString().trim();
    final name = nameRaw.isEmpty ? id : nameRaw;
    final repoUrl = (json['repoUrl'] ?? '').toString().trim();
    // 兼容旧插件配置，未填写作者时回退默认值，避免历史插件导入失败。
    final authorRaw = (json['author'] ?? '').toString().trim();
    final author = authorRaw.isEmpty ? 'Unknown' : authorRaw;
    final versionRaw = (json['version'] ?? '').toString().trim();
    final version = versionRaw.isEmpty ? '0.0.0' : versionRaw;
    final description = (json['description'] ?? '').toString().trim();
    final typeRaw = (json['type'] ?? '').toString().trim();
    final type = typeRaw.isEmpty ? 'python' : typeRaw;
    final pythonNamespace = (json['pythonNamespace'] ?? '').toString().trim();
    if (id.isEmpty) {
      throw const FormatException('插件字段不完整(id)');
    }
    // 清单列表阶段只解析基础信息，不在这里强制校验 pythonNamespace。
    // 真实运行时能力在插件安装后由插件自身 plugin.json 决定。

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
      repoUrl: repoUrl,
      author: author,
      description: description,
      version: version,
      type: type,
      pythonNamespace: pythonNamespace,
      providesGlobalPythonPaths: json['providesGlobalPythonPaths'] == true,
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
    final plugins = <PluginDefinition>[];
    for (final entry in rawPlugins.asMap().entries) {
      final item = entry.value;
      if (item is! Map) {
        // 单个插件格式错误时跳过，避免整个清单不可用。
        continue;
      }
      try {
        plugins.add(PluginDefinition.fromJson(Map<String, dynamic>.from(item)));
      } catch (_) {
        // 单个插件字段错误时跳过，保证其余插件仍可展示。
        continue;
      }
    }

    if (plugins.isEmpty) {
      throw const FormatException('清单中没有可用插件');
    }

    return PluginManifestV2(
      manifestVersion: manifestVersion,
      plugins: plugins,
    );
  }
}
