import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:now_chat/core/network/python_package_mirror_config.dart';
import 'package:now_chat/core/models/python_execution_result.dart';
import 'package:now_chat/core/models/python_plugin_manifest.dart';
import 'package:now_chat/util/app_logger.dart';
import 'package:path/path.dart' as p;

/// 插件包 SHA256 校验失败时抛出的异常，包含期望值与实际值。
class PythonPackageChecksumException implements Exception {
  final String packageId;
  final String expectedSha256;
  final String actualSha256;

  const PythonPackageChecksumException({
    required this.packageId,
    required this.expectedSha256,
    required this.actualSha256,
  });

  @override
  String toString() {
    return '校验值错误(package=$packageId, expected=$expectedSha256, actual=$actualSha256)';
  }
}

/// Python 插件核心能力：清单拉取、包安装、代码执行。
///
/// 该服务既支持桌面/本地 Python 进程模式，也支持 Android Chaquopy 桥接模式。
class PythonPluginService {
  final Dio _dio;
  static const MethodChannel _pythonBridge = MethodChannel(
    'nowchat/python_bridge',
  );
  static const EventChannel _pythonLogStream = EventChannel(
    'nowchat/python_bridge/log_stream',
  );

  /// 运行会话日志监听器：key=runId，用于把实时日志路由到对应执行请求。
  static final Map<String, void Function(_PythonLogEvent event)>
  _runLogListeners = <String, void Function(_PythonLogEvent event)>{};
  static StreamSubscription<dynamic>? _pythonLogSubscription;
  static final Random _random = Random();

  PythonPluginService({Dio? dio}) : _dio = dio ?? Dio();

  /// 拉取并解析远端插件清单。
  ///
  /// 与插件市场不同，这里解析的是 Python 库包清单（package 列表）。
  Future<PythonPluginManifest> fetchManifest(String manifestUrl) async {
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
    return PythonPluginManifest.fromJson(jsonMap);
  }

  /// 下载并安装插件包到指定目录，自动进行 SHA-256 校验。
  ///
  /// 安装逻辑是“覆盖式”：同 targetDir 会先清理再重装，避免旧文件残留。
  Future<void> installPackage({
    required PythonPluginPackage package,
    required Directory pluginRootDir,
    void Function(double progress)? onProgress,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('now_chat_python_');
    final tempZipFile = File(
      '${tempDir.path}${Platform.pathSeparator}${package.id}_${package.version}.zip',
    );
    final targetDir = Directory(
      '${pluginRootDir.path}${Platform.pathSeparator}${_normalizeRelativePath(package.targetDir)}',
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
      if (actualSha != expectedSha) {
        throw PythonPackageChecksumException(
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

      // 某些包会声明可执行入口（如脚本包装器），Android 下尝试补可执行权限。
      if (package.entryPoint != null && package.entryPoint!.trim().isNotEmpty) {
        final binary = File(
          '${targetDir.path}${Platform.pathSeparator}${_normalizeRelativePath(package.entryPoint!)}',
        );
        if (binary.existsSync()) {
          await _trySetExecutable(binary.path);
        }
      }
    } finally {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  /// 删除指定相对目录下的已安装包。
  Future<void> uninstallByRelativeDir({
    required Directory pluginRootDir,
    required String relativeTargetDir,
  }) async {
    final targetDir = Directory(
      '${pluginRootDir.path}${Platform.pathSeparator}${_normalizeRelativePath(relativeTargetDir)}',
    );
    if (targetDir.existsSync()) {
      await targetDir.delete(recursive: true);
    }
  }

  /// 按 requirements 安装插件 Python 依赖（插件隔离环境）。
  ///
  /// 设计要点：
  /// 1. 每个插件独立安装目录，允许同库不同版本并存。
  /// 2. 自动尝试多镜像，解决部分网络环境访问官方源失败的问题。
  /// 3. 对“未指定版本”按候选降序尝试，失败自动回退次新版本。
  Future<void> installRequirements({
    required String pluginId,
    required Directory pluginRootDir,
    required List<String> requirements,
    required String targetRelativeDir,
    void Function(double progress)? onProgress,
    String mirrorId = PythonPackageMirrorConfig.directId,
    String customMirrorBaseUrl = '',
  }) async {
    final normalizedRequirements =
        requirements
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
    if (normalizedRequirements.isEmpty) {
      return;
    }
    final normalizedTargetDir = _normalizeRelativePath(targetRelativeDir);
    if (normalizedTargetDir.isEmpty) {
      throw const FormatException('requirements 安装目录不能为空');
    }

    final installDir = Directory(
      p.join(pluginRootDir.path, normalizedTargetDir),
    );
    final cacheDir = Directory(
      p.join(pluginRootDir.path, '.pkg_cache', 'wheels'),
    );
    final lockFile = File(
      p.join(
        pluginRootDir.path,
        p.dirname(normalizedTargetDir),
        'plugin_requirements_lock.json',
      ),
    );

    if (installDir.existsSync()) {
      await installDir.delete(recursive: true);
    }
    await installDir.create(recursive: true);
    if (!cacheDir.existsSync()) {
      await cacheDir.create(recursive: true);
    }

    final preferredMirrorId = mirrorId.trim().isEmpty ? PythonPackageMirrorConfig.directId : mirrorId.trim();
    final mirrorIds = <String>[
      preferredMirrorId,
      ...PythonPackageMirrorConfig.automaticFallbackMirrorIds,
    ].toSet().toList();
    final lockPackages = <Map<String, dynamic>>[];
    final total = normalizedRequirements.length;

    AppLogger.i(
      '开始安装插件 requirements: plugin=$pluginId, count=$total, mirrorChain=$mirrorIds',
    );
    for (var index = 0; index < normalizedRequirements.length; index += 1) {
      final rawRequirement = normalizedRequirements[index];
      final spec = _RequirementSpec.parse(rawRequirement);
      onProgress?.call(index / total);
      AppLogger.i(
        '解析依赖: plugin=$pluginId, requirement=${spec.raw}, package=${spec.packageName}',
      );

      final candidates = await _resolveRequirementCandidates(
        spec: spec,
        mirrorIds: mirrorIds,
        customMirrorBaseUrl: customMirrorBaseUrl,
      );
      if (candidates.isEmpty) {
        throw Exception('未找到可安装依赖: ${spec.raw}');
      }

      _ResolvedRequirementCandidate? selectedCandidate;
      final fallbackTried = <Map<String, dynamic>>[];
      Object? lastError;
      for (final candidate in candidates) {
        try {
          final wheelFile = await _downloadWheelToCache(
            candidate: candidate,
            cacheDir: cacheDir,
          );
          await _extractZip(wheelFile, installDir);
          selectedCandidate = candidate;
          AppLogger.i(
            '依赖安装成功: plugin=$pluginId, package=${spec.packageName}, version=${candidate.version}, mirror=${candidate.mirrorId}',
          );
          break;
        } catch (e, st) {
          lastError = e;
          fallbackTried.add(<String, dynamic>{
            'version': candidate.version,
            'mirrorId': candidate.mirrorId,
            'error': e.toString(),
          });
          AppLogger.w(
            '依赖候选安装失败，尝试回退: plugin=$pluginId, package=${spec.packageName}, version=${candidate.version}, mirror=${candidate.mirrorId}, error=$e',
          );
          AppLogger.e('依赖候选安装异常', e, st);
        }
      }
      if (selectedCandidate == null) {
        throw Exception('依赖安装失败(${spec.raw}): ${lastError ?? "无可用候选"}');
      }

      lockPackages.add(<String, dynamic>{
        'requirement': spec.raw,
        'package': spec.packageName,
        'version': selectedCandidate.version,
        'mirrorId': selectedCandidate.mirrorId,
        'downloadUrl': selectedCandidate.downloadUrl,
        'sha256': selectedCandidate.sha256,
        'fallbackTried': fallbackTried,
      });
      onProgress?.call((index + 1) / total);
    }

    await lockFile.parent.create(recursive: true);
    final lockPayload = <String, dynamic>{
      'pluginId': pluginId,
      'resolvedAt': DateTime.now().toUtc().toIso8601String(),
      'targetDir': normalizedTargetDir,
      'requirements': normalizedRequirements,
      'packages': lockPackages,
    };
    await lockFile.writeAsString(jsonEncode(lockPayload));
    AppLogger.i(
      'requirements 安装完成: plugin=$pluginId, installed=${lockPackages.length}, lock=${lockFile.path}',
    );
    onProgress?.call(1);
  }

  /// 执行 Python 代码。
  ///
  /// Android: 通过 MethodChannel 调 Chaquopy（支持实时日志）。
  /// 其他平台: 启动外部 Python 进程执行。
  Future<PythonExecutionResult> executeCode({
    String? pythonBinaryPath,
    required String code,
    required Duration timeout,
    List<String>? extraSysPaths,
    String? logContext,
    Map<String, String>? environment,
    String? workingDirectory,
  }) async {
    if (Platform.isAndroid) {
      final runId = _buildRunId();
      // 先确保日志通道已建立，再注册本次 runId 监听，避免前几行日志丢失。
      await _ensurePythonLogStreamListening();
      _runLogListeners[runId] = (_PythonLogEvent event) {
        _emitRealtimePythonLog(event: event, logContext: logContext);
      };
      try {
        return _executeWithChaquopy(
          code: code,
          timeout: timeout,
          extraSysPaths: extraSysPaths ?? const <String>[],
          runId: runId,
          workingDirectory: workingDirectory,
        );
      } finally {
        _runLogListeners.remove(runId);
      }
    }

    if (pythonBinaryPath == null || pythonBinaryPath.trim().isEmpty) {
      throw Exception('未提供 Python 可执行文件路径');
    }

    final start = DateTime.now();
    final binaryFile = File(pythonBinaryPath);
    if (!binaryFile.existsSync()) {
      throw Exception('Python 运行时不存在: $pythonBinaryPath');
    }

    Process process;
    try {
      process = await Process.start(
        pythonBinaryPath,
        <String>['-c', code],
        environment: environment,
        workingDirectory: workingDirectory,
      );
    } on ProcessException catch (e) {
      throw Exception('启动 Python 失败: ${e.message}');
    }

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    final stdoutDone = process.stdout.transform(utf8.decoder).forEach((chunk) {
      stdoutBuffer.write(chunk);
    });
    final stderrDone = process.stderr.transform(utf8.decoder).forEach((chunk) {
      stderrBuffer.write(chunk);
    });

    int exitCode = -1;
    var timedOut = false;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
      exitCode = -1;
    } finally {
      await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
    }

    final duration = DateTime.now().difference(start);
    return PythonExecutionResult(
      stdout: stdoutBuffer.toString(),
      stderr: stderrBuffer.toString(),
      exitCode: exitCode,
      duration: duration,
      timedOut: timedOut,
    );
  }

  Future<PythonExecutionResult> _executeWithChaquopy({
    required String code,
    required Duration timeout,
    required List<String> extraSysPaths,
    required String runId,
    required String? workingDirectory,
  }) async {
    final normalizedPaths =
        extraSysPaths
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
    final rawResult = await _pythonBridge.invokeMethod<dynamic>(
      'executePython',
      <String, dynamic>{
        'code': code,
        'timeoutMs': timeout.inMilliseconds,
        'extraSysPaths': normalizedPaths,
        'runId': runId,
        // Android 侧通过该目录设置 Python cwd，避免脚本写入只读根目录。
        'workingDirectory': workingDirectory?.trim(),
      },
    );

    if (rawResult is! Map) {
      throw const FormatException('Python 桥接返回格式错误');
    }
    final result = Map<String, dynamic>.from(rawResult);
    final durationMsRaw = result['durationMs'];
    final durationMs =
        durationMsRaw is num ? durationMsRaw.toInt() : timeout.inMilliseconds;
    return PythonExecutionResult(
      stdout: (result['stdout'] ?? '').toString(),
      stderr: (result['stderr'] ?? '').toString(),
      exitCode:
          result['exitCode'] is num ? (result['exitCode'] as num).toInt() : -1,
      duration: Duration(milliseconds: durationMs),
      timedOut: result['timedOut'] == true,
    );
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
      final outPath =
          '${targetDir.path}${Platform.pathSeparator}$normalizedName';
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
    final segments =
        path
            .replaceAll('\\', '/')
            .split('/')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty && item != '.' && item != '..')
            .toList();
    return segments.join(Platform.pathSeparator);
  }

  Future<void> _trySetExecutable(String path) async {
    if (!Platform.isAndroid) return;
    try {
      await Process.run('chmod', <String>['755', path]);
    } catch (_) {
      // chmod 失败时不阻断安装流程，执行阶段会给出明确错误。
    }
  }

  /// 启动全局日志流监听，将原生事件按 runId 分发给对应执行会话。
  ///
  /// 该订阅只创建一次，全局复用，避免重复监听造成日志重复输出。
  static Future<void> _ensurePythonLogStreamListening() async {
    if (_pythonLogSubscription != null) return;
    _pythonLogSubscription = _pythonLogStream.receiveBroadcastStream().listen(
      (dynamic raw) {
        final event = _PythonLogEvent.tryParse(raw);
        if (event == null) return;
        final listener = _runLogListeners[event.runId];
        if (listener == null) return;
        listener(event);
      },
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.e('Python 实时日志通道异常', error, stackTrace);
      },
    );
  }

  /// 将原生日志转换为 AppLogger，便于 Flutter 侧统一检索与排查。
  static void _emitRealtimePythonLog({
    required _PythonLogEvent event,
    String? logContext,
  }) {
    final line = event.line.trimRight();
    if (line.isEmpty) return;
    final stream = event.stream.toLowerCase();
    final context = (logContext ?? '').trim();
    final prefix =
        context.isEmpty
            ? '[PyRT][${event.runId}][$stream]'
            : '[PyRT][$context][${event.runId}][$stream]';
    final chunks = _chunkForLog(line, 420);
    for (var i = 0; i < chunks.length; i += 1) {
      final chunk = chunks[i];
      final suffix = chunks.length > 1 ? ' (${i + 1}/${chunks.length})' : '';
      final message = '$prefix$suffix $chunk';
      if (stream == 'stderr') {
        final lower = chunk.toLowerCase();
        final isErrorLevel =
            lower.contains('traceback') ||
            lower.contains('exception') ||
            lower.contains('error');
        if (isErrorLevel) {
          AppLogger.e(message);
        } else {
          AppLogger.w(message);
        }
      } else {
        AppLogger.i(message);
      }
    }
  }

  /// 生成一次执行会话 ID，用于关联实时日志与请求结果。
  static String _buildRunId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = _random.nextInt(1 << 20).toRadixString(16);
    return 'py_$now$rand';
  }

  /// 分片长日志，避免单条日志过长导致展示与性能问题。
  static List<String> _chunkForLog(String message, int chunkSize) {
    if (message.length <= chunkSize) return <String>[message];
    final output = <String>[];
    for (var start = 0; start < message.length; start += chunkSize) {
      final end = min(start + chunkSize, message.length);
      output.add(message.substring(start, end));
    }
    return output;
  }

  /// 解析 requirements 候选版本列表，按“版本新 -> 旧”排序返回。
  ///
  /// 策略：
  /// 1. 按镜像优先级逐个请求 simple index。
  /// 2. 某镜像拿到可用候选后直接返回，降低跨镜像版本漂移。
  Future<List<_ResolvedRequirementCandidate>> _resolveRequirementCandidates({
    required _RequirementSpec spec,
    required List<String> mirrorIds,
    required String customMirrorBaseUrl,
  }) async {
    for (final mirrorId in mirrorIds) {
      final indexUrl = PythonPackageMirrorConfig.buildSimpleIndexUrl(
        packageName: spec.packageName,
        mirrorId: mirrorId,
        customMirrorBaseUrl: customMirrorBaseUrl,
      );
      try {
        final response = await _dio.getUri<String>(
          Uri.parse(indexUrl),
          options: Options(
            responseType: ResponseType.plain,
            validateStatus:
                (status) => status != null && status >= 200 && status < 500,
          ),
        );
        if (response.statusCode != 200) {
          AppLogger.w(
            '依赖索引请求失败: package=${spec.packageName}, mirror=$mirrorId, status=${response.statusCode}',
          );
          continue;
        }
        final candidates = _extractRequirementCandidatesFromSimpleIndex(
          spec: spec,
          indexUrl: indexUrl,
          simpleHtml: response.data ?? '',
          mirrorId: mirrorId,
        );
        if (candidates.isNotEmpty) {
          return candidates;
        }
      } catch (e, st) {
        AppLogger.w(
          '依赖索引解析失败: package=${spec.packageName}, mirror=$mirrorId, error=$e',
        );
        AppLogger.e('依赖索引解析异常', e, st);
      }
    }
    return const <_ResolvedRequirementCandidate>[];
  }

  /// 从 simple index 页面提取 wheel 候选。
  List<_ResolvedRequirementCandidate> _extractRequirementCandidatesFromSimpleIndex({
    required _RequirementSpec spec,
    required String indexUrl,
    required String simpleHtml,
    required String mirrorId,
  }) {
    if (simpleHtml.trim().isEmpty) {
      return const <_ResolvedRequirementCandidate>[];
    }
    final baseUri = Uri.parse(indexUrl);
    final links = RegExp(
      r'''href\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).allMatches(simpleHtml);
    if (links.isEmpty) {
      return const <_ResolvedRequirementCandidate>[];
    }

    // 相同版本可能存在多个 wheel（不同 ABI/平台），按分数保留最佳项。
    final bestByVersion = <String, _ResolvedRequirementCandidate>{};
    for (final link in links) {
      final hrefRaw = link.group(1);
      if (hrefRaw == null || hrefRaw.trim().isEmpty) continue;
      final href = _decodeSimpleHtmlHref(hrefRaw.trim());
      final resolvedUri = baseUri.resolve(href);
      final fileName =
          resolvedUri.pathSegments.isNotEmpty
              ? resolvedUri.pathSegments.last
              : '';
      if (fileName.isEmpty || !fileName.toLowerCase().endsWith('.whl')) {
        continue;
      }
      final score = _scoreWheelFilename(fileName);
      if (score < 0) continue;
      final version = _extractWheelVersionFromFilename(fileName);
      if (version.isEmpty || !spec.matches(version)) {
        continue;
      }
      final candidate = _ResolvedRequirementCandidate(
        packageName: spec.packageName,
        requested: spec.raw,
        version: version,
        downloadUrl: resolvedUri.toString(),
        sha256: _extractSha256FromFragment(resolvedUri.fragment),
        mirrorId: mirrorId,
        wheelScore: score,
        uploadedAt: null,
      );
      final existing = bestByVersion[version];
      if (existing == null || candidate.wheelScore > existing.wheelScore) {
        bestByVersion[version] = candidate;
      }
    }

    final candidates = bestByVersion.values.toList();

    // 默认按“版本新 -> 旧”排序；同版本优先 wheel 兼容分更高的候选。
    candidates.sort((a, b) {
      final byVersion = _compareVersionsLoose(b.version, a.version);
      if (byVersion != 0) return byVersion;
      final byScore = b.wheelScore.compareTo(a.wheelScore);
      if (byScore != 0) return byScore;
      return 0;
    });
    return candidates;
  }

  /// 解码 simple index 中的 HTML 属性文本（主要处理 `&amp;`）。
  String _decodeSimpleHtmlHref(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }

  /// 从 wheel 文件名解析版本号。
  ///
  /// wheel 命名：`{dist}-{version}(-{build})?-{py}-{abi}-{platform}.whl`
  String _extractWheelVersionFromFilename(String filename) {
    final lower = filename.toLowerCase();
    if (!lower.endsWith('.whl')) return '';
    final wheelName = lower.substring(0, lower.length - 4);
    final parts = wheelName.split('-');
    if (parts.length < 5) return '';
    return parts[1].trim();
  }

  /// 从 URL fragment 中提取 `sha256` 值（若不存在返回空字符串）。
  String _extractSha256FromFragment(String fragment) {
    if (fragment.trim().isEmpty) return '';
    final pairs = fragment.split('&');
    for (final pair in pairs) {
      final segments = pair.split('=');
      if (segments.length != 2) continue;
      if (segments[0].trim().toLowerCase() != 'sha256') continue;
      return segments[1].trim().toLowerCase();
    }
    return '';
  }

  /// 根据 wheel 文件名判断是否适配当前运行时，并计算候选优先级。
  int _scoreWheelFilename(String filename) {
    final lower = filename.toLowerCase();
    if (!lower.endsWith('.whl')) return -1;

    final wheelName = lower.substring(0, lower.length - 4);
    final parts = wheelName.split('-');
    if (parts.length < 5) return -1;
    final pythonTag = parts[parts.length - 3];
    final abiTag = parts[parts.length - 2];
    final platformTag = parts[parts.length - 1];

    final isPlatformAllowed =
        platformTag.contains('any') || platformTag.contains('android');
    if (!isPlatformAllowed) return -1;

    final isPythonAllowed =
        pythonTag.contains('py3') ||
        pythonTag.contains('py2.py3') ||
        pythonTag.contains('cp310');
    if (!isPythonAllowed) return -1;

    final isAbiAllowed =
        abiTag == 'none' || abiTag.contains('abi3') || abiTag.contains('cp310');
    if (!isAbiAllowed) return -1;

    var score = 0;
    if (platformTag.contains('android')) score += 120;
    if (platformTag.contains('arm64') || platformTag.contains('aarch64')) {
      score += 40;
    }
    if (platformTag.contains('any')) score += 80;
    if (pythonTag.contains('cp310')) score += 30;
    if (pythonTag.contains('py3')) score += 20;
    if (abiTag.contains('abi3')) score += 25;
    if (abiTag == 'none') score += 10;
    if (lower.contains('py3-none-any')) score += 120;
    return score;
  }

  /// 下载 wheel 到全局缓存目录，并执行 SHA-256 校验。
  Future<File> _downloadWheelToCache({
    required _ResolvedRequirementCandidate candidate,
    required Directory cacheDir,
  }) async {
    final uri = Uri.tryParse(candidate.downloadUrl);
    final fileName =
        (uri != null && uri.pathSegments.isNotEmpty)
            ? uri.pathSegments.last
            : '${candidate.packageName}-${candidate.version}.whl';
    final cacheFile = File(p.join(cacheDir.path, fileName));
    if (cacheFile.existsSync()) {
      if (candidate.sha256.isEmpty) return cacheFile;
      final localSha = await _calculateSha256(cacheFile);
      if (localSha.toLowerCase() == candidate.sha256.toLowerCase()) {
        return cacheFile;
      }
      await cacheFile.delete();
    }

    await _dio.download(candidate.downloadUrl, cacheFile.path);
    if (candidate.sha256.isNotEmpty) {
      final actualSha = await _calculateSha256(cacheFile);
      if (actualSha.toLowerCase() != candidate.sha256.toLowerCase()) {
        throw PythonPackageChecksumException(
          packageId: '${candidate.packageName}==${candidate.version}',
          expectedSha256: candidate.sha256.toLowerCase(),
          actualSha256: actualSha.toLowerCase(),
        );
      }
    }
    return cacheFile;
  }

  /// 宽松版本比较，用于按“新版本优先”排序与区间判断。
  ///
  /// 说明：这里不实现完整 PEP 440，仅覆盖常见 `x.y.z[-pre]` 形式。
  static int _compareVersionsLoose(String a, String b) {
    final leftTokens = _tokenizeVersion(a);
    final rightTokens = _tokenizeVersion(b);
    final maxLen = max(leftTokens.length, rightTokens.length);
    for (var i = 0; i < maxLen; i += 1) {
      final left = i < leftTokens.length ? leftTokens[i] : const _VersionToken.numeric(0);
      final right = i < rightTokens.length ? rightTokens[i] : const _VersionToken.numeric(0);
      if (left.isNumeric && right.isNumeric) {
        final cmp = left.numericValue.compareTo(right.numericValue);
        if (cmp != 0) return cmp;
        continue;
      }
      if (left.isNumeric && !right.isNumeric) return 1;
      if (!left.isNumeric && right.isNumeric) return -1;
      final cmp = left.textValue.compareTo(right.textValue);
      if (cmp != 0) return cmp;
    }
    return 0;
  }

  /// 将版本字符串拆分为“数字/文本”序列，便于宽松比较。
  static List<_VersionToken> _tokenizeVersion(String version) {
    final output = <_VersionToken>[];
    final normalized = version.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const <_VersionToken>[_VersionToken.numeric(0)];
    }
    final parts = normalized.split(RegExp(r'[\.\-_+]'));
    for (final part in parts) {
      if (part.trim().isEmpty) continue;
      final matches = RegExp(r'[0-9]+|[a-z]+').allMatches(part);
      if (matches.isEmpty) {
        output.add(_VersionToken.text(part));
        continue;
      }
      for (final match in matches) {
        final token = match.group(0) ?? '';
        if (token.isEmpty) continue;
        final number = int.tryParse(token);
        if (number != null) {
          output.add(_VersionToken.numeric(number));
        } else {
          output.add(_VersionToken.text(token));
        }
      }
    }
    if (output.isEmpty) {
      return const <_VersionToken>[_VersionToken.numeric(0)];
    }
    return output;
  }
}

/// Python 实时日志事件。
class _PythonLogEvent {
  final String runId;
  final String stream;
  final String line;

  const _PythonLogEvent({
    required this.runId,
    required this.stream,
    required this.line,
  });

  /// 解析 EventChannel 原生日志事件。
  static _PythonLogEvent? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final runId = (map['runId'] ?? '').toString().trim();
    final stream = (map['stream'] ?? '').toString().trim();
    final line = (map['line'] ?? '').toString();
    if (runId.isEmpty || stream.isEmpty) return null;
    return _PythonLogEvent(runId: runId, stream: stream, line: line);
  }
}

/// requirements 单条声明解析结果。
class _RequirementSpec {
  final String raw;
  final String packageName;
  final List<_RequirementConstraint> constraints;

  const _RequirementSpec({
    required this.raw,
    required this.packageName,
    required this.constraints,
  });

  /// 解析 requirement 文本（支持 `name` / `name==x` / 区间比较组合）。
  static _RequirementSpec parse(String input) {
    final raw = input.trim();
    if (raw.isEmpty) {
      throw const FormatException('requirements 条目不能为空');
    }
    final match = RegExp(r'^([A-Za-z0-9_.-]+)\s*(.*)$').firstMatch(raw);
    if (match == null) {
      throw FormatException('requirements 条目格式错误: $raw');
    }
    final packageName = (match.group(1) ?? '').trim().toLowerCase();
    final specRaw = (match.group(2) ?? '').trim();
    if (packageName.isEmpty) {
      throw FormatException('requirements 包名为空: $raw');
    }
    if (specRaw.isEmpty) {
      return _RequirementSpec(
        raw: raw,
        packageName: packageName,
        constraints: const <_RequirementConstraint>[],
      );
    }

    final constraints = <_RequirementConstraint>[];
    final tokens = specRaw.split(',');
    for (final tokenRaw in tokens) {
      final token = tokenRaw.trim();
      if (token.isEmpty) continue;
      final opMatch = RegExp(r'^(==|>=|<=|>|<)\s*([A-Za-z0-9_.+\-]+)$').firstMatch(token);
      if (opMatch == null) {
        throw FormatException('暂不支持的版本约束: $raw');
      }
      constraints.add(
        _RequirementConstraint(
          operator: opMatch.group(1)!,
          version: opMatch.group(2)!.trim(),
        ),
      );
    }
    return _RequirementSpec(
      raw: raw,
      packageName: packageName,
      constraints: constraints,
    );
  }

  /// 判断指定版本是否满足当前 requirements 约束。
  bool matches(String version) {
    if (constraints.isEmpty) return true;
    for (final constraint in constraints) {
      final cmp = PythonPluginService._compareVersionsLoose(
        version,
        constraint.version,
      );
      switch (constraint.operator) {
        case '==':
          if (cmp != 0) return false;
          break;
        case '>=':
          if (cmp < 0) return false;
          break;
        case '<=':
          if (cmp > 0) return false;
          break;
        case '>':
          if (cmp <= 0) return false;
          break;
        case '<':
          if (cmp >= 0) return false;
          break;
      }
    }
    return true;
  }
}

/// 单个 requirements 约束条件（如 `>=1.2.0`）。
class _RequirementConstraint {
  final String operator;
  final String version;

  const _RequirementConstraint({required this.operator, required this.version});
}

/// 已解析的依赖安装候选。
class _ResolvedRequirementCandidate {
  final String packageName;
  final String requested;
  final String version;
  final String downloadUrl;
  final String sha256;
  final String mirrorId;
  final int wheelScore;
  final DateTime? uploadedAt;

  const _ResolvedRequirementCandidate({
    required this.packageName,
    required this.requested,
    required this.version,
    required this.downloadUrl,
    required this.sha256,
    required this.mirrorId,
    required this.wheelScore,
    required this.uploadedAt,
  });
}

/// 版本比较的 token（数字或文本）。
class _VersionToken {
  final int? _number;
  final String? _text;

  const _VersionToken.numeric(int value)
    : _number = value,
      _text = null;

  const _VersionToken.text(String value)
    : _number = null,
      _text = value;

  bool get isNumeric => _number != null;
  int get numericValue => _number ?? 0;
  String get textValue => _text ?? '';
}
