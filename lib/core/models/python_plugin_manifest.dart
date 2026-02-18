/// Python 插件包信息（核心包与库包共用）。
class PythonPluginPackage {
  final String id;
  final String name;
  final String description;
  final String version;
  final String url;
  final String sha256;
  final int? sizeBytes;

  /// 解压安装到插件根目录下的相对路径，如 `core/3.11.8`。
  final String targetDir;

  /// 运行时追加到 PYTHONPATH 的相对目录列表。
  final List<String> pythonPathEntries;

  /// 仅核心包需要：Python 可执行文件相对路径，如 `bin/python3`。
  final String? entryPoint;

  const PythonPluginPackage({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.url,
    required this.sha256,
    required this.targetDir,
    required this.pythonPathEntries,
    this.entryPoint,
    this.sizeBytes,
  });

  factory PythonPluginPackage.fromJson(
    Map<String, dynamic> json, {
    bool requireDownloadFields = true,
    String context = 'package',
  }) {
    final id = (json['id'] ?? '').toString().trim();
    final name = (json['name'] ?? '').toString().trim();
    final description = (json['description'] ?? '').toString().trim();
    final version = (json['version'] ?? '').toString().trim();
    final url = (json['url'] ?? '').toString().trim();
    final sha256 = (json['sha256'] ?? '').toString().trim().toLowerCase();
    final targetDir = (json['targetDir'] ?? '').toString().trim();
    final entryPoint = (json['entryPoint'] ?? '').toString().trim();
    final rawPythonPathEntries = json['pythonPathEntries'];
    final pythonPathEntries =
        rawPythonPathEntries is List
            ? rawPythonPathEntries
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

    return PythonPluginPackage(
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
      entryPoint: entryPoint.isEmpty ? null : entryPoint,
    );
  }
}

/// Python 插件清单：包含核心包与可选库包。
class PythonPluginManifest {
  final int manifestVersion;
  final PythonPluginPackage core;
  final List<PythonPluginPackage> libraries;

  const PythonPluginManifest({
    required this.manifestVersion,
    required this.core,
    required this.libraries,
  });

  factory PythonPluginManifest.fromJson(Map<String, dynamic> json) {
    final manifestVersion =
        json['manifestVersion'] is num
            ? (json['manifestVersion'] as num).toInt()
            : 1;
    final pluginContainer = _findPythonPluginContainer(json);
    final coreRaw = pluginContainer != null ? pluginContainer['core'] : json['core'];
    if (coreRaw is! Map<String, dynamic>) {
      throw const FormatException('清单缺少核心包信息');
    }
    final librariesRaw =
        pluginContainer != null ? pluginContainer['libraries'] : json['libraries'];
    final libraries =
        librariesRaw is List
            ? librariesRaw.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                if (item is! Map) {
                  throw FormatException('插件包字段不完整(library#$index): item');
                }
                final map = Map<String, dynamic>.from(item);
                final idPreview = (map['id'] ?? '').toString().trim();
                final contextLabel =
                    idPreview.isEmpty
                        ? 'library#$index'
                        : 'library:$idPreview';
                return PythonPluginPackage.fromJson(
                  map,
                  requireDownloadFields: true,
                  context: contextLabel,
                );
              }).toList()
            : const <PythonPluginPackage>[];

    final core = PythonPluginPackage.fromJson(
      coreRaw,
      // Android 下核心运行时由 Chaquopy 内置，允许 core 的下载字段为空。
      requireDownloadFields: false,
      context: 'core',
    );
    if ((core.entryPoint ?? '').isEmpty) {
      throw const FormatException('核心包缺少 entryPoint');
    }

    return PythonPluginManifest(
      manifestVersion: manifestVersion,
      core: core,
      libraries: libraries,
    );
  }

  static Map<String, dynamic>? _findPythonPluginContainer(
    Map<String, dynamic> json,
  ) {
    final pluginsRaw = json['plugins'];
    if (pluginsRaw is! List) return null;
    for (final item in pluginsRaw) {
      if (item is! Map) continue;
      final plugin = Map<String, dynamic>.from(item);
      final pluginId = (plugin['id'] ?? '').toString().trim().toLowerCase();
      final pluginType = (plugin['type'] ?? '').toString().trim().toLowerCase();
      if (pluginId == 'python' || pluginType == 'python') {
        return plugin;
      }
    }
    return null;
  }
}

/// 已安装库包的本地记录。
class InstalledPythonLibrary {
  final String id;
  final String version;
  final String targetDir;
  final List<String> pythonPathEntries;

  const InstalledPythonLibrary({
    required this.id,
    required this.version,
    required this.targetDir,
    required this.pythonPathEntries,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'version': version,
      'targetDir': targetDir,
      'pythonPathEntries': pythonPathEntries,
    };
  }

  factory InstalledPythonLibrary.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString().trim();
    final version = (json['version'] ?? '').toString().trim();
    final targetDir = (json['targetDir'] ?? '').toString().trim();
    final pathEntriesRaw = json['pythonPathEntries'];
    final pythonPathEntries =
        pathEntriesRaw is List
            ? pathEntriesRaw
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty)
                .toList()
            : const <String>[];
    if (id.isEmpty || version.isEmpty || targetDir.isEmpty) {
      throw const FormatException('已安装库记录字段不完整');
    }
    return InstalledPythonLibrary(
      id: id,
      version: version,
      targetDir: targetDir,
      pythonPathEntries:
          pythonPathEntries.isEmpty ? const <String>['.'] : pythonPathEntries,
    );
  }
}
