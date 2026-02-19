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
    return PluginManifestV2.fromJson(jsonMap);
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
