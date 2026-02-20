import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:now_chat/core/network/github_mirror_config.dart';
import 'package:now_chat/core/models/plugin_manifest_v2.dart';
import 'package:now_chat/util/app_logger.dart';
import 'package:path/path.dart' as p;

typedef PluginGithubMirrorPreset = GithubMirrorPreset;

/// 插件包校验失败异常，包含期望与实际 SHA256。
class PluginPackageChecksumException implements Exception {
  final String packageId;
  final String expectedSha256;
  final String actualSha256;

  const PluginPackageChecksumException({
    required this.packageId,
    required this.expectedSha256,
    required this.actualSha256,
  });

  @override
  String toString() {
    return '校验值错误(package=$packageId, expected=$expectedSha256, actual=$actualSha256)';
  }
}

/// 本地 zip 导入结果：包含插件定义与原文件路径。
class LocalPluginImportPayload {
  final PluginDefinition plugin;
  final String sourceZipPath;

  const LocalPluginImportPayload({
    required this.plugin,
    required this.sourceZipPath,
  });
}

/// 插件服务：负责清单拉取、zip 安装与本地导入解析。
///
/// 说明：
/// - 这里处理“插件分发层”能力（manifest/repo/zip），不参与运行时执行。
/// - 运行时工具与 Hook 注册由 `PluginRegistry` 和 `PluginHookBus` 接管。
class PluginService {
  static const String githubMirrorDirect = GithubMirrorConfig.directId;
  static const String githubMirrorGhfast = GithubMirrorConfig.ghfastId;
  static const String githubMirrorGhLlkk = GithubMirrorConfig.ghllkkId;
  static const String githubMirrorGhproxyNet = GithubMirrorConfig.ghproxyNetId;
  static const String githubMirrorCustom = GithubMirrorConfig.customId;

  /// 插件中心镜像预设由统一配置中心维护。
  static const List<PluginGithubMirrorPreset> githubMirrorPresets =
      GithubMirrorConfig.presets;

  final Dio _dio;

  PluginService({Dio? dio}) : _dio = dio ?? Dio();

  /// 读取并解析通用插件清单。
  ///
  /// 流程：
  /// 1. 先获取基础清单（支持 asset:// 与 http(s)）。
  /// 2. 再按 `repoUrl` 补全每个插件的最新 plugin.json 元数据。
  /// 3. 补全失败时回退到基础清单（避免“单插件异常拖垮整个市场”）。
  Future<PluginManifestV2> fetchManifest(
    String manifestUrl, {
    String mirrorId = githubMirrorDirect,
    String customMirrorBaseUrl = '',
  }) async {
    final normalizedUrl = manifestUrl.trim();
    if (normalizedUrl.isEmpty) {
      throw const FormatException('清单地址不能为空');
    }
    AppLogger.i('开始加载插件清单: $normalizedUrl');

    dynamic data;
    if (normalizedUrl.startsWith('asset://')) {
      final assetPath = normalizedUrl.substring('asset://'.length);
      if (assetPath.trim().isEmpty) {
        throw const FormatException('asset 清单路径不能为空');
      }
      final raw = await rootBundle.loadString(assetPath);
      data = raw;
    } else {
      final requestUrl = _applyMirrorToUrl(
        normalizedUrl,
        mirrorId: mirrorId,
        customMirrorBaseUrl: customMirrorBaseUrl,
      );
      final response = await _dio.getUri<dynamic>(Uri.parse(requestUrl));
      if (response.statusCode != 200) {
        throw Exception('清单请求失败: ${response.statusCode}');
      }
      data = response.data;
    }

    Map<String, dynamic> jsonMap;
    if (data is Map<String, dynamic>) {
      jsonMap = data;
    } else if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('清单格式错误');
      }
      jsonMap = decoded;
    } else {
      throw const FormatException('清单格式错误');
    }
    final baseManifest = PluginManifestV2.fromJson(jsonMap);
    final enrichedPlugins = <PluginDefinition>[];
    for (final plugin in baseManifest.plugins) {
      final repoUrl = plugin.repoUrl.trim();
      if (repoUrl.isEmpty) {
        enrichedPlugins.add(plugin);
        continue;
      }
      try {
        final repoPlugin = await fetchPluginDefinitionFromRepo(
          repoUrl,
          mirrorId: mirrorId,
          customMirrorBaseUrl: customMirrorBaseUrl,
        );
        // 清单 ID 优先，避免仓库内误改 id 导致本地安装记录失配。
        final merged = repoPlugin.copyWith(id: plugin.id, repoUrl: repoUrl);
        enrichedPlugins.add(merged);
      } catch (_) {
        // 仓库解析失败时，保留清单基础信息，至少能显示列表项。
        AppLogger.w('插件仓库信息加载失败，回退清单基础信息: ${plugin.id}');
        enrichedPlugins.add(plugin);
      }
    }

    final manifest = PluginManifestV2(
      manifestVersion: baseManifest.manifestVersion,
      plugins: enrichedPlugins,
    );
    AppLogger.i(
      '插件清单加载完成: manifestVersion=${manifest.manifestVersion}, plugins=${manifest.plugins.length}',
    );
    return manifest;
  }

  /// 下载并安装远程插件包。
  ///
  /// 这里主要用于 package 级资源下载（非仓库插件）。
  /// 安装前会做 SHA256 校验，防止传输损坏或镜像返回错误包。
  Future<void> installPackageFromUrl({
    required PluginPackage package,
    required Directory pluginRootDir,
    void Function(double progress)? onProgress,
  }) async {
    AppLogger.i(
      '开始安装插件包: id=${package.id}, version=${package.version}, url=${package.url}',
    );
    final tempDir = await Directory.systemTemp.createTemp('now_chat_plugin_');
    final tempZipFile = File(
      '${tempDir.path}${Platform.pathSeparator}${package.id}_${package.version}.zip',
    );
    final targetDir = Directory(
      p.join(pluginRootDir.path, _normalizeRelativePath(package.targetDir)),
    );

    try {
      await _dio.download(
        package.url,
        tempZipFile.path,
        onReceiveProgress: (received, total) {
          if (onProgress == null || total <= 0) return;
          onProgress(received / total);
        },
      );

      final digest = await _calculateSha256(tempZipFile);
      final expectedSha = package.sha256.toLowerCase();
      final actualSha = digest.toLowerCase();
      if (expectedSha.isNotEmpty && expectedSha != actualSha) {
        throw PluginPackageChecksumException(
          packageId: package.id,
          expectedSha256: expectedSha,
          actualSha256: actualSha,
        );
      }

      if (targetDir.existsSync()) {
        await targetDir.delete(recursive: true);
      }
      await targetDir.create(recursive: true);
      await _extractZip(tempZipFile, targetDir);
      AppLogger.i('插件包安装完成: id=${package.id}, target=${targetDir.path}');
    } finally {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  /// 根据 Git 仓库链接安装插件（下载仓库 zip 并解压）。
  ///
  /// 当前仅支持 GitHub 仓库地址，会按 `main`、`master` 顺序尝试下载。
  Future<PluginDefinition> installPluginFromRepo({
    required String repoUrl,
    required Directory pluginRootDir,
    required String targetDir,
    void Function(double progress)? onProgress,
    String mirrorId = githubMirrorDirect,
    String customMirrorBaseUrl = '',
  }) async {
    AppLogger.i('开始从仓库安装插件: repo=$repoUrl, targetDir=$targetDir');
    final tempDir = await Directory.systemTemp.createTemp(
      'now_chat_plugin_git_',
    );
    final tempZipFile = File(
      '${tempDir.path}${Platform.pathSeparator}plugin_repo.zip',
    );
    final installDir = Directory(
      p.join(pluginRootDir.path, _normalizeRelativePath(targetDir)),
    );

    try {
      // 自动尝试 main/master，兼容不同仓库默认分支。
      await _downloadGitRepoArchive(
        repoUrl: repoUrl,
        outputZipPath: tempZipFile.path,
        onProgress: onProgress,
        mirrorId: mirrorId,
        customMirrorBaseUrl: customMirrorBaseUrl,
      );

      if (installDir.existsSync()) {
        await installDir.delete(recursive: true);
      }
      await installDir.create(recursive: true);

      // GitHub 仓库 zip 通常包含一级根目录，这里统一剥离。
      await _extractZipFlattenRoot(tempZipFile, installDir);
      final plugin = await parsePluginDefinitionFromDirectory(installDir);
      AppLogger.i('仓库插件安装完成: id=${plugin.id}, version=${plugin.version}');
      return plugin;
    } finally {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  /// 从本地 zip 导入插件定义。
  ///
  /// 仅支持 zip，且不会在此步骤安装，只做“选择 + 元数据预览”。
  Future<LocalPluginImportPayload?> pickAndParseLocalPluginZip() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const <String>['zip'],
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    final zipPath = (file.path ?? '').trim();
    if (zipPath.isEmpty) {
      throw const FormatException('无法读取本地 zip 路径');
    }
    AppLogger.i('选择本地插件包: $zipPath');
    final plugin = await parsePluginDefinitionFromZip(File(zipPath));
    AppLogger.i('本地插件解析完成: id=${plugin.id}, version=${plugin.version}');
    return LocalPluginImportPayload(plugin: plugin, sourceZipPath: zipPath);
  }

  /// 从 zip 中读取 `plugin.json` 并解析插件定义。
  ///
  /// 兼容两种常见布局：
  /// - 根目录直接有 `plugin.json`
  /// - 顶层目录下包含 `plugin.json`
  Future<PluginDefinition> parsePluginDefinitionFromZip(File zipFile) async {
    if (!zipFile.existsSync()) {
      throw Exception('插件包不存在: ${zipFile.path}');
    }
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    ArchiveFile? pluginFile;
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final normalized = entry.name.replaceAll('\\', '/').toLowerCase();
      if (normalized == 'plugin.json' || normalized.endsWith('/plugin.json')) {
        pluginFile = entry;
        break;
      }
    }
    if (pluginFile == null) {
      throw const FormatException('插件包缺少 plugin.json');
    }
    final contentBytes = pluginFile.content as List<int>;
    final raw = utf8.decode(contentBytes);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('plugin.json 格式错误');
    }
    return PluginDefinition.fromJson(decoded);
  }

  /// 从已解压目录中读取 `plugin.json` 并解析插件定义。
  ///
  /// 若存在多个 `plugin.json`，优先选择路径最短的那个，减少误选子模块配置。
  Future<PluginDefinition> parsePluginDefinitionFromDirectory(
    Directory pluginDir,
  ) async {
    if (!pluginDir.existsSync()) {
      throw Exception('插件目录不存在: ${pluginDir.path}');
    }
    final candidates =
        pluginDir
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where(
              (item) => p.basename(item.path).toLowerCase() == 'plugin.json',
            )
            .toList();
    if (candidates.isEmpty) {
      throw const FormatException('插件目录缺少 plugin.json');
    }
    candidates.sort((a, b) => a.path.length.compareTo(b.path.length));
    final raw = await candidates.first.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('plugin.json 格式错误');
    }
    return PluginDefinition.fromJson(decoded);
  }

  /// 安装本地插件 zip 到指定 target 目录。
  Future<void> installPackageFromLocalZip({
    required String sourceZipPath,
    required Directory pluginRootDir,
    required String targetDir,
  }) async {
    final sourceFile = File(sourceZipPath);
    if (!sourceFile.existsSync()) {
      throw Exception('本地插件包不存在: $sourceZipPath');
    }
    final installDir = Directory(
      p.join(pluginRootDir.path, _normalizeRelativePath(targetDir)),
    );
    if (installDir.existsSync()) {
      await installDir.delete(recursive: true);
    }
    await installDir.create(recursive: true);
    await _extractZip(sourceFile, installDir);
  }

  /// 删除指定安装目录。
  Future<void> uninstallByRelativeDir({
    required Directory pluginRootDir,
    required String relativeTargetDir,
  }) async {
    final targetDir = Directory(
      p.join(pluginRootDir.path, _normalizeRelativePath(relativeTargetDir)),
    );
    if (targetDir.existsSync()) {
      AppLogger.i('删除插件目录: ${targetDir.path}');
      await targetDir.delete(recursive: true);
    }
  }

  Future<String> calculateFileSha256(File file) async {
    return _calculateSha256(file);
  }

  /// 从 GitHub 仓库拉取 README 文本。
  ///
  /// 按 main/master + 大小写文件名顺序尝试，提高兼容性。
  Future<String> fetchReadmeFromRepo(
    String repoUrl, {
    String mirrorId = githubMirrorDirect,
    String customMirrorBaseUrl = '',
  }) async {
    final (owner, repo) = _parseGithubOwnerRepo(repoUrl);
    final candidates = <String>[
      'https://raw.githubusercontent.com/$owner/$repo/main/README.md',
      'https://raw.githubusercontent.com/$owner/$repo/master/README.md',
      'https://raw.githubusercontent.com/$owner/$repo/main/readme.md',
      'https://raw.githubusercontent.com/$owner/$repo/master/readme.md',
    ];

    Object? lastError;
    for (final url in candidates) {
      try {
        final requestUrl = _applyMirrorToUrl(
          url,
          mirrorId: mirrorId,
          customMirrorBaseUrl: customMirrorBaseUrl,
        );
        final response = await _dio.getUri<String>(
          Uri.parse(requestUrl),
          options: Options(responseType: ResponseType.plain),
        );
        if (response.statusCode == 200) {
          final content = (response.data ?? '').trim();
          if (content.isNotEmpty) {
            return content;
          }
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) continue;
        lastError = e;
        break;
      } catch (e) {
        lastError = e;
        break;
      }
    }

    if (lastError != null) {
      throw Exception('读取 README 失败: $lastError');
    }
    throw Exception('仓库未找到 README.md');
  }

  /// 从 GitHub 仓库拉取并解析 `plugin.json`。
  ///
  /// 远程安装与市场展示都依赖该方法获取插件真实元数据。
  Future<PluginDefinition> fetchPluginDefinitionFromRepo(
    String repoUrl, {
    String mirrorId = githubMirrorDirect,
    String customMirrorBaseUrl = '',
  }) async {
    AppLogger.i('开始读取仓库插件定义: $repoUrl');
    final (owner, repo) = _parseGithubOwnerRepo(repoUrl);
    final candidates = <String>[
      'https://raw.githubusercontent.com/$owner/$repo/main/plugin.json',
      'https://raw.githubusercontent.com/$owner/$repo/master/plugin.json',
    ];
    Object? lastError;
    for (final url in candidates) {
      try {
        final requestUrl = _applyMirrorToUrl(
          url,
          mirrorId: mirrorId,
          customMirrorBaseUrl: customMirrorBaseUrl,
        );
        final response = await _dio.getUri<String>(
          Uri.parse(requestUrl),
          options: Options(responseType: ResponseType.plain),
        );
        if (response.statusCode == 200) {
          final raw = (response.data ?? '').trim();
          if (raw.isEmpty) continue;
          final decoded = jsonDecode(raw);
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('plugin.json 格式错误');
          }
          final plugin = PluginDefinition.fromJson(
            decoded,
          ).copyWith(repoUrl: repoUrl);
          AppLogger.i('仓库插件定义读取完成: id=${plugin.id}, version=${plugin.version}');
          return plugin;
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) continue;
        lastError = e;
        break;
      } catch (e) {
        lastError = e;
        break;
      }
    }

    if (lastError != null) {
      throw Exception('读取 plugin.json 失败: $lastError');
    }
    throw Exception('仓库未找到 plugin.json');
  }

  Future<String> _calculateSha256(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString().toLowerCase();
  }

  Future<void> _extractZip(File zipFile, Directory targetDir) async {
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    for (final entry in archive) {
      final normalizedName = _normalizeRelativePath(entry.name);
      if (normalizedName.isEmpty) continue;
      final outPath = p.join(targetDir.path, normalizedName);
      if (entry.isFile) {
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(entry.content as List<int>);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
  }

  /// 解压 zip 并自动去掉 GitHub 仓库压缩包的顶层目录。
  ///
  /// 这样安装目录会直接落到插件内容，避免出现 `<plugin>/<repo-main>/...` 嵌套。
  Future<void> _extractZipFlattenRoot(File zipFile, Directory targetDir) async {
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final firstSegments = <String>{};
    for (final entry in archive) {
      final normalized = _normalizeRelativePath(entry.name);
      if (normalized.isEmpty) continue;
      final parts = normalized.split(p.separator);
      if (parts.isNotEmpty) {
        firstSegments.add(parts.first);
      }
    }
    final hasSingleRoot = firstSegments.length == 1;
    final rootPrefix =
        hasSingleRoot ? '${firstSegments.first}${p.separator}' : '';

    for (final entry in archive) {
      var normalizedName = _normalizeRelativePath(entry.name);
      if (normalizedName.isEmpty) continue;
      if (hasSingleRoot && normalizedName.startsWith(rootPrefix)) {
        normalizedName = normalizedName.substring(rootPrefix.length);
      }
      if (normalizedName.isEmpty) continue;
      final outPath = p.join(targetDir.path, normalizedName);
      if (entry.isFile) {
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(entry.content as List<int>);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
  }

  Future<void> _downloadGitRepoArchive({
    required String repoUrl,
    required String outputZipPath,
    void Function(double progress)? onProgress,
    String mirrorId = githubMirrorDirect,
    String customMirrorBaseUrl = '',
  }) async {
    final normalizedRepoUrl = _normalizeGitRepoUrl(repoUrl);
    final candidates = <String>[
      '$normalizedRepoUrl/archive/refs/heads/main.zip',
      '$normalizedRepoUrl/archive/refs/heads/master.zip',
    ];
    DioException? lastDioError;
    for (final candidateUrl in candidates) {
      try {
        final requestUrl = _applyMirrorToUrl(
          candidateUrl,
          mirrorId: mirrorId,
          customMirrorBaseUrl: customMirrorBaseUrl,
        );
        await _dio.download(
          requestUrl,
          outputZipPath,
          onReceiveProgress: (received, total) {
            if (onProgress == null || total <= 0) return;
            onProgress(received / total);
          },
        );
        return;
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          lastDioError = e;
          continue;
        }
        rethrow;
      }
    }
    throw Exception(
      '下载仓库压缩包失败(main/master): ${lastDioError ?? normalizedRepoUrl}',
    );
  }

  String _normalizeGitRepoUrl(String repoUrl) {
    var normalized = repoUrl.trim();
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.endsWith('.git')) {
      normalized = normalized.substring(0, normalized.length - 4);
    }
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      throw Exception('不支持的仓库链接: $repoUrl');
    }
    return normalized;
  }

  (String, String) _parseGithubOwnerRepo(String repoUrl) {
    final normalized = _normalizeGitRepoUrl(repoUrl);
    final uri = Uri.parse(normalized);
    if (uri.host.toLowerCase() != 'github.com') {
      throw Exception('当前仅支持 GitHub 仓库: $repoUrl');
    }
    final segments = uri.pathSegments.where((item) => item.isNotEmpty).toList();
    if (segments.length < 2) {
      throw Exception('仓库链接格式错误: $repoUrl');
    }
    return (segments[0], segments[1]);
  }

  /// 对 GitHub 相关链接应用镜像规则；非 GitHub 链接保持原样。
  ///
  /// 仅代理 GitHub 域名，避免无关第三方链接被错误重写。
  String _applyMirrorToUrl(
    String url, {
    required String mirrorId,
    String customMirrorBaseUrl = '',
  }) {
    return GithubMirrorConfig.applyMirrorToUrl(
      url: url,
      mirrorId: mirrorId,
      customMirrorBaseUrl: customMirrorBaseUrl,
      onlyGithubHosts: true,
    );
  }

  /// 规范化用户输入的自定义代理地址。
  /// 返回空字符串代表输入无效。
  static String normalizeCustomMirrorBaseUrl(String input) {
    return GithubMirrorConfig.normalizeCustomBaseUrl(input);
  }

  /// 对镜像做轻量测速（返回耗时毫秒，失败返回 null）。
  ///
  /// 注意：这里只用于“可用性判断”，不代表真实下载吞吐。
  Future<int?> probeMirrorLatency({
    required String mirrorId,
    String customMirrorBaseUrl = '',
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final probeTarget =
        'https://raw.githubusercontent.com/CikeSeven/NowChat/main/plugin_manifest.json';
    final requestUrl = _applyMirrorToUrl(
      probeTarget,
      mirrorId: mirrorId,
      customMirrorBaseUrl: customMirrorBaseUrl,
    );
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _dio.getUri<String>(
        Uri.parse(requestUrl),
        options: Options(
          responseType: ResponseType.plain,
          sendTimeout: timeout,
          receiveTimeout: timeout,
          validateStatus:
              (status) => status != null && status >= 200 && status < 500,
        ),
      );
      stopwatch.stop();
      final statusCode = response.statusCode ?? 0;
      if (statusCode >= 200 && statusCode < 400) {
        return stopwatch.elapsedMilliseconds;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String _normalizeRelativePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments =
        normalized
            .split('/')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty && item != '.' && item != '..')
            .toList();
    return p.joinAll(segments);
  }
}
