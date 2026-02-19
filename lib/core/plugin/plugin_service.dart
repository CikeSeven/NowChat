import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:now_chat/core/models/plugin_manifest_v2.dart';
import 'package:path/path.dart' as p;

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
class PluginService {
  final Dio _dio;

  PluginService({Dio? dio}) : _dio = dio ?? Dio();

  /// 读取并解析通用插件清单。
  Future<PluginManifestV2> fetchManifest(String manifestUrl) async {
    final normalizedUrl = manifestUrl.trim();
    if (normalizedUrl.isEmpty) {
      throw const FormatException('清单地址不能为空');
    }

    dynamic data;
    if (normalizedUrl.startsWith('asset://')) {
      final assetPath = normalizedUrl.substring('asset://'.length);
      if (assetPath.trim().isEmpty) {
        throw const FormatException('asset 清单路径不能为空');
      }
      final raw = await rootBundle.loadString(assetPath);
      data = raw;
    } else {
      final response = await _dio.getUri<dynamic>(Uri.parse(normalizedUrl));
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
        final repoPlugin = await fetchPluginDefinitionFromRepo(repoUrl);
        // 清单 ID 优先，避免仓库变更 ID 导致本地记录对不上。
        final merged = repoPlugin.copyWith(
          id: plugin.id,
          repoUrl: repoUrl,
        );
        enrichedPlugins.add(merged);
      } catch (_) {
        // 仓库解析失败时，保留清单基础信息，至少能显示列表项。
        enrichedPlugins.add(plugin);
      }
    }

    return PluginManifestV2(
      manifestVersion: baseManifest.manifestVersion,
      plugins: enrichedPlugins,
    );
  }

  /// 下载并安装远程插件包。
  Future<void> installPackageFromUrl({
    required PluginPackage package,
    required Directory pluginRootDir,
    void Function(double progress)? onProgress,
  }) async {
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
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('now_chat_plugin_git_');
    final tempZipFile = File(
      '${tempDir.path}${Platform.pathSeparator}plugin_repo.zip',
    );
    final installDir = Directory(
      p.join(pluginRootDir.path, _normalizeRelativePath(targetDir)),
    );

    try {
      await _downloadGitRepoArchive(
        repoUrl: repoUrl,
        outputZipPath: tempZipFile.path,
        onProgress: onProgress,
      );

      if (installDir.existsSync()) {
        await installDir.delete(recursive: true);
      }
      await installDir.create(recursive: true);

      await _extractZipFlattenRoot(tempZipFile, installDir);
      return parsePluginDefinitionFromDirectory(installDir);
    } finally {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  /// 从本地 zip 导入插件定义。
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
    final plugin = await parsePluginDefinitionFromZip(File(zipPath));
    return LocalPluginImportPayload(plugin: plugin, sourceZipPath: zipPath);
  }

  /// 从 zip 中读取 `plugin.json` 并解析插件定义。
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
  Future<PluginDefinition> parsePluginDefinitionFromDirectory(
    Directory pluginDir,
  ) async {
    if (!pluginDir.existsSync()) {
      throw Exception('插件目录不存在: ${pluginDir.path}');
    }
    final candidates = pluginDir
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((item) => p.basename(item.path).toLowerCase() == 'plugin.json')
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
      await targetDir.delete(recursive: true);
    }
  }

  Future<String> calculateFileSha256(File file) async {
    return _calculateSha256(file);
  }

  /// 从 GitHub 仓库拉取 README 文本。
  Future<String> fetchReadmeFromRepo(String repoUrl) async {
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
        final response = await _dio.getUri<String>(
          Uri.parse(url),
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
  Future<PluginDefinition> fetchPluginDefinitionFromRepo(String repoUrl) async {
    final (owner, repo) = _parseGithubOwnerRepo(repoUrl);
    final candidates = <String>[
      'https://raw.githubusercontent.com/$owner/$repo/main/plugin.json',
      'https://raw.githubusercontent.com/$owner/$repo/master/plugin.json',
    ];
    Object? lastError;
    for (final url in candidates) {
      try {
        final response = await _dio.getUri<String>(
          Uri.parse(url),
          options: Options(responseType: ResponseType.plain),
        );
        if (response.statusCode == 200) {
          final raw = (response.data ?? '').trim();
          if (raw.isEmpty) continue;
          final decoded = jsonDecode(raw);
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('plugin.json 格式错误');
          }
          return PluginDefinition.fromJson(decoded).copyWith(repoUrl: repoUrl);
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
  }) async {
    final normalizedRepoUrl = _normalizeGitRepoUrl(repoUrl);
    final candidates = <String>[
      '$normalizedRepoUrl/archive/refs/heads/main.zip',
      '$normalizedRepoUrl/archive/refs/heads/master.zip',
    ];
    DioException? lastDioError;
    for (final candidateUrl in candidates) {
      try {
        await _dio.download(
          candidateUrl,
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
