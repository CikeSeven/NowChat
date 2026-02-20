/// 已安装插件包记录。
class InstalledPluginPackageRecord {
  /// 插件包 ID（来自 plugin.json packages[].id）。
  final String id;

  /// 插件包版本号。
  final String version;

  /// 安装目标目录（相对 plugin_runtime 根目录）。
  final String targetDir;

  /// 该包对 Python 运行时追加的 sys.path 条目。
  final List<String> pythonPathEntries;

  /// 可选入口脚本（用于插件侧自定义启动逻辑）。
  final String? entryPoint;

  const InstalledPluginPackageRecord({
    required this.id,
    required this.version,
    required this.targetDir,
    required this.pythonPathEntries,
    this.entryPoint,
  });

  /// 序列化单个包安装记录。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'version': version,
      'targetDir': targetDir,
      'pythonPathEntries': pythonPathEntries,
      'entryPoint': entryPoint,
    };
  }

  /// 从 JSON 恢复包安装记录，并做基础字段校验。
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
  /// 插件 ID。
  final String pluginId;

  /// 插件版本号。
  final String pluginVersion;

  /// 插件是否启用（暂停时为 false）。
  final bool enabled;

  /// 当前启用的工具名列表。
  final List<String> enabledTools;

  /// 该插件安装的包记录列表。
  final List<InstalledPluginPackageRecord> packages;

  /// 插件安装时间。
  final DateTime installedAt;

  /// 是否来自本地导入（true=本地 zip，false=远程仓库安装）。
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

  /// 复制插件安装记录并返回新实例。
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

  /// 序列化插件安装记录。
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

  /// 从 JSON 恢复插件安装记录，并兜底处理可选字段。
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
        DateTime.tryParse(installedAtRaw) ??
        DateTime.fromMillisecondsSinceEpoch(0);

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
