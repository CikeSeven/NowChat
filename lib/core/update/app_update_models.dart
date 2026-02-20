/// GitHub Release 资源项（仅保留应用更新所需字段）。
class AppReleaseAsset {
  /// 资源名（例如 `app-arm64-v8a-release.apk`）。
  final String name;

  /// 原始下载链接（GitHub release 资产地址）。
  final String downloadUrl;

  /// 资源大小（字节）。
  final int size;

  /// MIME 类型。
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
  /// Release 标签（通常为版本号，例如 `v0.5.5+10`）。
  final String tagName;

  /// Release 标题。
  final String name;

  /// 发布说明正文。
  final String body;

  /// 发布时间。
  final DateTime? publishedAt;

  /// Release 网页链接。
  final String htmlUrl;

  /// 资产列表。
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
  /// 是否检测到新版本。
  final bool hasUpdate;

  /// 当前应用版本号。
  final String currentVersion;

  /// 远端最新版本号。
  final String latestVersion;

  /// 远端 release 详情。
  final AppReleaseInfo releaseInfo;

  /// 选中的安装资产（优先 arm64 apk）。
  final AppReleaseAsset? selectedAsset;

  /// 经过镜像转换后的最终下载链接。
  final String resolvedDownloadUrl;

  /// 本次成功请求所用镜像 ID。
  final String usedMirrorId;

  /// 本次成功请求所用镜像展示名。
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
