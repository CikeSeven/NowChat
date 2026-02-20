import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:now_chat/core/models/python_execution_result.dart';
import 'package:now_chat/core/models/python_plugin_manifest.dart';
import 'package:now_chat/util/app_logger.dart';

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
