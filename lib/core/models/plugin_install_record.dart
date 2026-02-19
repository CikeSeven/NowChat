/// 已安装插件包记录。
class InstalledPluginPackageRecord {
  final String id;
  final String version;
  final String targetDir;
  final List<String> pythonPathEntries;
  final String? entryPoint;

  const InstalledPluginPackageRecord({
    required this.id,
    required this.version,
    required this.targetDir,
    required this.pythonPathEntries,
    this.entryPoint,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'version': version,
      'targetDir': targetDir,
      'pythonPathEntries': pythonPathEntries,
      'entryPoint': entryPoint,
    };
  }

  factory InstalledPluginPackageRecord.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString().trim();
    final version = (json['version'] ?? '').toString().trim();
    final targetDir = (json['targetDir'] ?? '').toString().trim();
    final entryPointRaw = (json['entryPoint'] ?? '').toString().trim();
    final rawPathEntries = json['pythonPathEntries'];
    final pythonPathEntries =
        rawPathEntries is List
            ? rawPathEntries
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty)
                .toList()
            : const <String>[];
    if (id.isEmpty || version.isEmpty || targetDir.isEmpty) {
      throw const FormatException('插件包安装记录字段不完整');
    }
    return InstalledPluginPackageRecord(
      id: id,
      version: version,
      targetDir: targetDir,
      pythonPathEntries:
          pythonPathEntries.isEmpty ? const <String>['.'] : pythonPathEntries,
      entryPoint: entryPointRaw.isEmpty ? null : entryPointRaw,
    );
  }
}

/// 已安装插件记录：状态、包信息与工具开关。
class InstalledPluginRecord {
  final String pluginId;
  final String pluginVersion;
  final bool enabled;
  final List<String> enabledTools;
  final List<InstalledPluginPackageRecord> packages;
  final DateTime installedAt;
  final bool isLocalImport;

  const InstalledPluginRecord({
    required this.pluginId,
    required this.pluginVersion,
    required this.enabled,
    required this.enabledTools,
    required this.packages,
    required this.installedAt,
    required this.isLocalImport,
  });

  InstalledPluginRecord copyWith({
    bool? enabled,
    List<String>? enabledTools,
    List<InstalledPluginPackageRecord>? packages,
    DateTime? installedAt,
    String? pluginVersion,
    bool? isLocalImport,
  }) {
    return InstalledPluginRecord(
      pluginId: pluginId,
      pluginVersion: pluginVersion ?? this.pluginVersion,
      enabled: enabled ?? this.enabled,
      enabledTools: enabledTools ?? this.enabledTools,
      packages: packages ?? this.packages,
      installedAt: installedAt ?? this.installedAt,
      isLocalImport: isLocalImport ?? this.isLocalImport,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pluginId': pluginId,
      'pluginVersion': pluginVersion,
      'enabled': enabled,
      'enabledTools': enabledTools,
      'packages': packages.map((item) => item.toJson()).toList(),
      'installedAt': installedAt.toIso8601String(),
      'isLocalImport': isLocalImport,
    };
  }

  factory InstalledPluginRecord.fromJson(Map<String, dynamic> json) {
    final pluginId = (json['pluginId'] ?? '').toString().trim();
    final pluginVersion = (json['pluginVersion'] ?? '').toString().trim();
    if (pluginId.isEmpty || pluginVersion.isEmpty) {
      throw const FormatException('插件安装记录字段不完整');
    }

    final rawEnabledTools = json['enabledTools'];
    final enabledTools =
        rawEnabledTools is List
            ? rawEnabledTools
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty)
                .toList()
            : const <String>[];

    final rawPackages = json['packages'];
    final packages =
        rawPackages is List
            ? rawPackages
                .whereType<Map>()
                .map(
                  (item) => InstalledPluginPackageRecord.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
            : const <InstalledPluginPackageRecord>[];

    final installedAtRaw = (json['installedAt'] ?? '').toString().trim();
    final installedAt =
        DateTime.tryParse(installedAtRaw) ?? DateTime.fromMillisecondsSinceEpoch(0);

    return InstalledPluginRecord(
      pluginId: pluginId,
      pluginVersion: pluginVersion,
      enabled: json['enabled'] != false,
      enabledTools: enabledTools,
      packages: packages,
      installedAt: installedAt,
      isLocalImport: json['isLocalImport'] == true,
    );
  }
}
