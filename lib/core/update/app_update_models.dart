/// GitHub Release 资源项（仅保留应用更新所需字段）。
class AppReleaseAsset {
  final String name;
  final String downloadUrl;
  final int size;
  final String contentType;

  const AppReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    required this.contentType,
  });
}

/// GitHub Release 信息模型。
class AppReleaseInfo {
  final String tagName;
  final String name;
  final String body;
  final DateTime? publishedAt;
  final String htmlUrl;
  final List<AppReleaseAsset> assets;

  const AppReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.publishedAt,
    required this.htmlUrl,
    required this.assets,
  });
}

/// 更新检查结果：包含版本比较结果、下载链接与本次使用的代理信息。
class AppUpdateCheckResult {
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final AppReleaseInfo releaseInfo;
  final AppReleaseAsset? selectedAsset;
  final String resolvedDownloadUrl;
  final String usedMirrorId;
  final String usedMirrorName;

  const AppUpdateCheckResult({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseInfo,
    required this.selectedAsset,
    required this.resolvedDownloadUrl,
    required this.usedMirrorId,
    required this.usedMirrorName,
  });
}
