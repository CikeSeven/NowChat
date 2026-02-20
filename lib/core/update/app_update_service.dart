import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:now_chat/core/network/github_mirror_config.dart';
import 'package:now_chat/core/update/app_update_models.dart';
import 'package:now_chat/util/app_logger.dart';

/// 应用更新服务：从 GitHub Release 获取最新版，并在直连失败时自动代理回退。
class AppUpdateService {
  static const String _owner = 'CikeSeven';
  static const String _repo = 'NowChat';

  final Dio _dio;

  AppUpdateService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 12),
              sendTimeout: const Duration(seconds: 8),
            ),
          );

  /// 检查最新版本。
  ///
  /// 顺序尝试直连与内置代理，首个成功结果即返回。
  Future<AppUpdateCheckResult> checkLatestRelease({
    required String currentVersion,
  }) async {
    final normalizedCurrent = currentVersion.trim();
    if (normalizedCurrent.isEmpty) {
      throw Exception('当前版本号为空');
    }

    final releaseApiUrl =
        'https://api.github.com/repos/$_owner/$_repo/releases/latest';
    Object? lastError;
    GithubMirrorPreset? usedMirror;
    AppReleaseInfo? releaseInfo;

    for (final mirrorId in GithubMirrorConfig.automaticFallbackMirrorIds) {
      final mirror = GithubMirrorConfig.findById(mirrorId);
      if (mirror == null) continue;
      final requestUrl = GithubMirrorConfig.applyMirrorToUrl(
        url: releaseApiUrl,
        mirrorId: mirror.id,
        onlyGithubHosts: true,
      );
      try {
        AppLogger.i('检查更新请求: mirror=${mirror.id}, url=$requestUrl');
        final response = await _dio.getUri<dynamic>(
          Uri.parse(requestUrl),
          options: Options(
            headers: const <String, String>{
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
            },
          ),
        );
        final statusCode = response.statusCode ?? 0;
        if (statusCode < 200 || statusCode >= 300) {
          throw Exception('HTTP $statusCode');
        }
        releaseInfo = _parseReleaseInfo(response.data);
        usedMirror = mirror;
        break;
      } catch (e, st) {
        lastError = e;
        AppLogger.w('检查更新失败，尝试下一个代理: mirror=${mirror.id}, error=$e');
        AppLogger.e('检查更新请求异常', e, st);
      }
    }

    if (releaseInfo == null || usedMirror == null) {
      throw Exception('无法获取最新版本信息: $lastError');
    }

    final latestVersion = _extractVersionFromRelease(releaseInfo);
    final hasUpdate = isRemoteVersionNewer(
      currentVersion: normalizedCurrent,
      latestVersion: latestVersion,
    );
    final selectedAsset = pickPreferredApkAsset(releaseInfo.assets);
    final resolvedDownloadUrl =
        selectedAsset == null
            ? ''
            : GithubMirrorConfig.applyMirrorToUrl(
              url: selectedAsset.downloadUrl,
              mirrorId: usedMirror.id,
              onlyGithubHosts: true,
            );

    return AppUpdateCheckResult(
      hasUpdate: hasUpdate,
      currentVersion: normalizedCurrent,
      latestVersion: latestVersion,
      releaseInfo: releaseInfo,
      selectedAsset: selectedAsset,
      resolvedDownloadUrl: resolvedDownloadUrl,
      usedMirrorId: usedMirror.id,
      usedMirrorName: usedMirror.name,
    );
  }

  /// 版本比较：支持 `x.y.z+build` 与 `v` 前缀。
  bool isRemoteVersionNewer({
    required String currentVersion,
    required String latestVersion,
  }) {
    final current = _parseVersion(currentVersion);
    final latest = _parseVersion(latestVersion);
    if (current == null || latest == null) {
      AppLogger.w(
        '版本号解析失败，回退为“不同即更新”: current=$currentVersion, latest=$latestVersion',
      );
      return _normalizeVersionText(latestVersion) !=
          _normalizeVersionText(currentVersion);
    }
    if (latest.major != current.major) return latest.major > current.major;
    if (latest.minor != current.minor) return latest.minor > current.minor;
    if (latest.patch != current.patch) return latest.patch > current.patch;
    return latest.build > current.build;
  }

  /// 选择 APK 资源：优先 arm64-v8a，否则取第一个可用 APK。
  AppReleaseAsset? pickPreferredApkAsset(List<AppReleaseAsset> assets) {
    if (assets.isEmpty) return null;
    final apkAssets =
        assets.where((item) => item.name.toLowerCase().endsWith('.apk')).toList();
    if (apkAssets.isEmpty) return null;
    apkAssets.sort((a, b) {
      final pa = _apkPriority(a.name);
      final pb = _apkPriority(b.name);
      if (pa != pb) return pa.compareTo(pb);
      return a.name.compareTo(b.name);
    });
    return apkAssets.first;
  }

  AppReleaseInfo _parseReleaseInfo(dynamic rawData) {
    Map<String, dynamic> jsonMap;
    if (rawData is Map<String, dynamic>) {
      jsonMap = rawData;
    } else if (rawData is String) {
      final decoded = jsonDecode(rawData);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Release 响应格式错误');
      }
      jsonMap = decoded;
    } else {
      throw const FormatException('Release 响应格式错误');
    }

    final tagName = (jsonMap['tag_name'] ?? '').toString().trim();
    final name = (jsonMap['name'] ?? '').toString().trim();
    final body = (jsonMap['body'] ?? '').toString();
    final htmlUrl = (jsonMap['html_url'] ?? '').toString().trim();
    final publishedAtRaw = (jsonMap['published_at'] ?? '').toString().trim();
    final publishedAt =
        publishedAtRaw.isEmpty ? null : DateTime.tryParse(publishedAtRaw);

    final rawAssets = jsonMap['assets'];
    final assets = <AppReleaseAsset>[];
    if (rawAssets is List) {
      for (final item in rawAssets) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final name = (map['name'] ?? '').toString().trim();
        final downloadUrl = (map['browser_download_url'] ?? '').toString().trim();
        if (name.isEmpty || downloadUrl.isEmpty) continue;
        final sizeRaw = map['size'];
        final size =
            sizeRaw is num ? sizeRaw.toInt() : int.tryParse('$sizeRaw') ?? 0;
        final contentType = (map['content_type'] ?? '').toString().trim();
        assets.add(
          AppReleaseAsset(
            name: name,
            downloadUrl: downloadUrl,
            size: size,
            contentType: contentType,
          ),
        );
      }
    }

    if (tagName.isEmpty && name.isEmpty) {
      throw const FormatException('Release 缺少版本号字段');
    }

    return AppReleaseInfo(
      tagName: tagName,
      name: name,
      body: body,
      publishedAt: publishedAt,
      htmlUrl: htmlUrl,
      assets: assets,
    );
  }

  String _extractVersionFromRelease(AppReleaseInfo releaseInfo) {
    final tag = releaseInfo.tagName.trim();
    if (tag.isNotEmpty) return _normalizeVersionText(tag);
    return _normalizeVersionText(releaseInfo.name);
  }

  int _apkPriority(String name) {
    final lowerName = name.toLowerCase();
    if (lowerName.contains('arm64-v8a')) return 0;
    return 1;
  }

  _ParsedVersion? _parseVersion(String rawVersion) {
    final normalized = _normalizeVersionText(rawVersion);
    if (normalized.isEmpty) return null;
    final parts = normalized.split('+');
    final semver = parts.first.trim();
    final build = parts.length > 1 ? _parseInt(parts[1]) : 0;
    if (build == null) return null;
    final semverParts = semver.split('.');
    final major = semverParts.isNotEmpty ? _parseInt(semverParts[0]) : 0;
    final minor = semverParts.length > 1 ? _parseInt(semverParts[1]) : 0;
    final patch = semverParts.length > 2 ? _parseInt(semverParts[2]) : 0;
    if (major == null || minor == null || patch == null) return null;
    return _ParsedVersion(major: major, minor: minor, patch: patch, build: build);
  }

  int? _parseInt(String input) {
    final match = RegExp(r'\d+').firstMatch(input.trim());
    if (match == null) return null;
    return int.tryParse(match.group(0)!);
  }

  String _normalizeVersionText(String version) {
    var normalized = version.trim();
    if (normalized.startsWith('v') || normalized.startsWith('V')) {
      normalized = normalized.substring(1);
    }
    return normalized.trim();
  }
}

/// 版本结构体：用于可比较的数字版本。
class _ParsedVersion {
  final int major;
  final int minor;
  final int patch;
  final int build;

  const _ParsedVersion({
    required this.major,
    required this.minor,
    required this.patch,
    required this.build,
  });
}
