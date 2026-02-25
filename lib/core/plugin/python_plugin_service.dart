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
  static const String _sourceChaquopy = 'chaquopy';
  static const String _sourcePypi = 'pypi';
  static const String _runtimePythonVersion = '3.10';
  static const String _runtimeSysPlatform = 'linux';
  static const String _runtimePlatformSystem = 'linux';
  static const String _runtimeOsName = 'posix';

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
    final pypiFallbackSources = PythonPackageMirrorConfig.pypiFallbackSimpleBaseUrls;
    final lockPackages = <Map<String, dynamic>>[];
    final pendingQueue =
        normalizedRequirements
            .map(
              (item) => _PendingRequirement(
                requirement: item,
                source: 'manifest',
              ),
            )
            .toList();
    final queuedPackageNames = <String>{
      ...pendingQueue.map(
        (item) => _RequirementSpec.parse(item.requirement).packageName,
      ),
    };
    final installedByPackage = <String, _ResolvedRequirementCandidate>{};

    AppLogger.i(
      '开始安装插件 requirements: plugin=$pluginId, count=${normalizedRequirements.length}, mirrorChain=$mirrorIds, pypiFallback=$pypiFallbackSources',
    );
    while (pendingQueue.isNotEmpty) {
      final pending = pendingQueue.removeAt(0);
      final spec = _RequirementSpec.parse(pending.requirement);
      queuedPackageNames.remove(spec.packageName);

      final installed = installedByPackage[spec.packageName];
      if (installed != null) {
        // 若同包重复声明但版本约束冲突，直接失败，避免运行期出现不可预测行为。
        if (!spec.matches(installed.version)) {
          throw Exception(
            '依赖版本冲突: ${spec.raw} 与已安装 ${installed.packageName}==${installed.version}',
          );
        }
        continue;
      }

      final completed = installedByPackage.length;
      final dynamicTotal = completed + pendingQueue.length + 1;
      onProgress?.call(completed / dynamicTotal);
      AppLogger.i(
        '解析依赖: plugin=$pluginId, requirement=${spec.raw}, package=${spec.packageName}, source=${pending.source}',
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
      File? selectedWheelFile;
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
          selectedWheelFile = wheelFile;
          AppLogger.i(
            '依赖安装成功: plugin=$pluginId, package=${spec.packageName}, version=${candidate.version}, source=${candidate.sourceType}, mirror=${candidate.mirrorId}',
          );
          break;
        } catch (e, st) {
          lastError = e;
          fallbackTried.add(<String, dynamic>{
            'version': candidate.version,
            'mirrorId': candidate.mirrorId,
            'sourceType': candidate.sourceType,
            'error': e.toString(),
          });
          AppLogger.w(
            '依赖候选安装失败，尝试回退: plugin=$pluginId, package=${spec.packageName}, version=${candidate.version}, source=${candidate.sourceType}, mirror=${candidate.mirrorId}, error=$e',
          );
          AppLogger.e('依赖候选安装异常', e, st);
        }
      }
      if (selectedCandidate == null || selectedWheelFile == null) {
        throw Exception('依赖安装失败(${spec.raw}): ${lastError ?? "无可用候选"}');
      }

      installedByPackage[spec.packageName] = selectedCandidate;
      final discoveredRequirements = await _extractTransitiveRequirementsFromWheel(
        wheelFile: selectedWheelFile,
        sourcePackage: selectedCandidate.packageName,
      );
      final discoveredForLock = <String>[];
      for (final dependency in discoveredRequirements) {
        final dependencySpec = _RequirementSpec.parse(dependency.requirement);
        final dependencyPackage = dependencySpec.packageName;
        if (installedByPackage.containsKey(dependencyPackage) ||
            queuedPackageNames.contains(dependencyPackage)) {
          continue;
        }
        pendingQueue.add(
          _PendingRequirement(
            requirement: dependency.requirement,
            source: selectedCandidate.packageName,
          ),
        );
        queuedPackageNames.add(dependencyPackage);
        discoveredForLock.add(dependency.requirement);
        AppLogger.i(
          '发现传递依赖: plugin=$pluginId, parent=${selectedCandidate.packageName}, requirement=${dependency.requirement}',
        );
      }

      lockPackages.add(<String, dynamic>{
        'requirement': spec.raw,
        'sourceRequirement': pending.source,
        'package': spec.packageName,
        'version': selectedCandidate.version,
        'sourceType': selectedCandidate.sourceType,
        'mirrorId': selectedCandidate.mirrorId,
        'indexUrl': selectedCandidate.indexUrl,
        'downloadUrl': selectedCandidate.downloadUrl,
        'sha256': selectedCandidate.sha256,
        'discoveredDependencies': discoveredForLock,
        'fallbackTried': fallbackTried,
      });

      final completedAfter = installedByPackage.length;
      final dynamicTotalAfter = completedAfter + pendingQueue.length;
      final progress =
          dynamicTotalAfter == 0 ? 1.0 : completedAfter / dynamicTotalAfter;
      onProgress?.call(progress);
    }

    await lockFile.parent.create(recursive: true);
    final lockPayload = <String, dynamic>{
      'pluginId': pluginId,
      'resolvedAt': DateTime.now().toUtc().toIso8601String(),
      'targetDir': normalizedTargetDir,
      'requirements': normalizedRequirements,
      'mirrorChain': mirrorIds,
      'pypiFallback': pypiFallbackSources,
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
    final packageNameCandidates = _buildPackageNameCandidates(spec.packageName);
    // 第一阶段：优先 Chaquopy 源，尽量命中 Android 预编译 wheel。
    for (final mirrorId in mirrorIds) {
      for (final packageNameCandidate in packageNameCandidates) {
        final indexUrls = PythonPackageMirrorConfig.buildSimpleIndexUrls(
          packageName: packageNameCandidate,
          mirrorId: mirrorId,
          customMirrorBaseUrl: customMirrorBaseUrl,
        );
        for (final indexUrl in indexUrls) {
          try {
            final response = await _fetchSimpleIndexWithRetry(indexUrl);
            if (response.statusCode != 200) {
              AppLogger.w(
                '依赖索引请求失败: package=${spec.packageName}, mirror=$mirrorId, url=$indexUrl, status=${response.statusCode}',
              );
              continue;
            }
            final candidates = _extractRequirementCandidatesFromSimpleIndex(
              spec: spec,
              indexUrl: indexUrl,
              simpleHtml: response.data ?? '',
              mirrorId: mirrorId,
              sourceType: _sourceChaquopy,
            );
            if (candidates.isNotEmpty) {
              return candidates;
            }
          } catch (e, st) {
            AppLogger.w(
              '依赖索引解析失败: package=${spec.packageName}, mirror=$mirrorId, url=$indexUrl, error=$e',
            );
            AppLogger.e('依赖索引解析异常', e, st);
          }
        }
      }
    }

    // 第二阶段：Chaquopy 不可用时，回退到 PyPI simple（国内镜像优先）。
    for (final simpleBaseUrl in PythonPackageMirrorConfig.pypiFallbackSimpleBaseUrls) {
      final fallbackMirrorId = simpleBaseUrl.contains('tuna.tsinghua.edu.cn')
          ? 'pypi_tsinghua'
          : 'pypi_official';
      for (final packageNameCandidate in packageNameCandidates) {
        final indexUrls = PythonPackageMirrorConfig.buildPypiSimpleIndexUrls(
          packageName: packageNameCandidate,
          simpleBaseUrl: simpleBaseUrl,
        );
        for (final indexUrl in indexUrls) {
          try {
            final response = await _fetchSimpleIndexWithRetry(indexUrl);
            if (response.statusCode != 200) {
              AppLogger.w(
                '依赖索引请求失败: package=${spec.packageName}, mirror=$fallbackMirrorId, url=$indexUrl, status=${response.statusCode}',
              );
              continue;
            }
            final candidates = _extractRequirementCandidatesFromSimpleIndex(
              spec: spec,
              indexUrl: indexUrl,
              simpleHtml: response.data ?? '',
              mirrorId: fallbackMirrorId,
              sourceType: _sourcePypi,
            );
            if (candidates.isNotEmpty) {
              AppLogger.i(
                '依赖解析回退到 PyPI: package=${spec.packageName}, mirror=$fallbackMirrorId, candidates=${candidates.length}',
              );
              return candidates;
            }
          } catch (e, st) {
            AppLogger.w(
              '依赖索引解析失败: package=${spec.packageName}, mirror=$fallbackMirrorId, url=$indexUrl, error=$e',
            );
            AppLogger.e('依赖索引解析异常', e, st);
          }
        }
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
    required String sourceType,
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
      // PyPI 回退阶段只允许纯 Python wheel，避免安装到不兼容的本地动态库。
      if (sourceType == _sourcePypi &&
          !fileName.toLowerCase().contains('py3-none-any')) {
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
        sourceType: sourceType,
        indexUrl: indexUrl,
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

  /// 构建包名候选，兼容不同仓库对 `-/_/.` 的目录命名差异。
  List<String> _buildPackageNameCandidates(String packageName) {
    final raw = packageName.trim().toLowerCase();
    if (raw.isEmpty) return const <String>[];
    final candidates = <String>[
      raw,
      raw.replaceAll('-', '_'),
      raw.replaceAll('_', '-'),
      raw.replaceAll('.', '-'),
      raw.replaceAll('.', '_'),
      raw.replaceAll(RegExp(r'[-_.]+'), '-'),
      raw.replaceAll(RegExp(r'[-_.]+'), '_'),
    ];
    return candidates.toSet().where((item) => item.trim().isNotEmpty).toList();
  }

  /// 请求 simple index，并在可重试网络异常时自动重试。
  ///
  /// 背景：
  /// - 某些移动网络下会出现 `Connection closed before full header was received`。
  /// - 这种错误通常是链路抖动，重试后可恢复。
  Future<Response<String>> _fetchSimpleIndexWithRetry(
    String indexUrl, {
    int maxAttempts = 3,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      try {
        final response = await _dio.getUri<String>(
          Uri.parse(indexUrl),
          options: Options(
            responseType: ResponseType.plain,
            validateStatus:
                (status) => status != null && status >= 200 && status < 500,
            headers: const <String, dynamic>{
              // 显式关闭长连接，降低某些代理链路下的半连接问题。
              'Connection': 'close',
            },
            sendTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 20),
          ),
        );
        return response;
      } catch (e) {
        lastError = e;
        final shouldRetry = _isRetriableSimpleIndexError(e);
        if (!shouldRetry || attempt >= maxAttempts) {
          rethrow;
        }
        AppLogger.w(
          '依赖索引请求重试: url=$indexUrl, attempt=$attempt/$maxAttempts, error=$e',
        );
        await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
      }
    }
    throw Exception('依赖索引请求失败: $lastError');
  }

  /// 判断 simple index 请求异常是否可重试。
  bool _isRetriableSimpleIndexError(Object error) {
    if (error is DioException) {
      final type = error.type;
      if (type == DioExceptionType.connectionError ||
          type == DioExceptionType.connectionTimeout ||
          type == DioExceptionType.receiveTimeout ||
          type == DioExceptionType.sendTimeout ||
          type == DioExceptionType.unknown) {
        return true;
      }
      final raw = (error.error?.toString() ?? '').toLowerCase();
      if (raw.contains('connection closed before full header') ||
          raw.contains('connection reset') ||
          raw.contains('socketexception')) {
        return true;
      }
    }
    return false;
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

  /// 从 wheel 的 METADATA 中提取传递依赖（Requires-Dist）。
  ///
  /// 说明：
  /// 1. 该方法只解析并返回“下一层依赖声明”，由安装主循环继续递归处理。
  /// 2. marker 条件会在解析阶段按当前 Android/Python 运行时进行过滤。
  Future<List<_TransitiveRequirement>> _extractTransitiveRequirementsFromWheel({
    required File wheelFile,
    required String sourcePackage,
  }) async {
    if (!wheelFile.existsSync()) {
      return const <_TransitiveRequirement>[];
    }
    final bytes = await wheelFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    ArchiveFile? metadataEntry;
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final normalized = entry.name.replaceAll('\\', '/').toLowerCase();
      if (normalized.endsWith('.dist-info/metadata')) {
        metadataEntry = entry;
        break;
      }
    }
    if (metadataEntry == null) {
      return const <_TransitiveRequirement>[];
    }
    final metadataRaw = utf8.decode(
      metadataEntry.content as List<int>,
      allowMalformed: true,
    );
    final requiresDistValues = _readMetadataHeaderValues(
      metadataRaw,
      headerName: 'Requires-Dist',
    );
    if (requiresDistValues.isEmpty) {
      return const <_TransitiveRequirement>[];
    }

    final dependencies = <_TransitiveRequirement>[];
    for (final requiresDist in requiresDistValues) {
      final normalizedRequirement = _normalizeRequiresDistRequirement(
        requiresDist,
      );
      if (normalizedRequirement == null ||
          normalizedRequirement.trim().isEmpty) {
        continue;
      }
      dependencies.add(
        _TransitiveRequirement(
          requirement: normalizedRequirement,
          source: sourcePackage,
        ),
      );
    }
    return dependencies;
  }

  /// 读取 Python package metadata 的指定头部（兼容续行语法）。
  List<String> _readMetadataHeaderValues(
    String metadataRaw, {
    required String headerName,
  }) {
    final headerKey = headerName.trim().toLowerCase();
    final output = <String>[];
    String? activeHeader;
    final activeValue = StringBuffer();

    void flushActiveHeader() {
      if ((activeHeader ?? '').toLowerCase() != headerKey) return;
      final value = activeValue.toString().trim();
      if (value.isNotEmpty) {
        output.add(value);
      }
    }

    for (final rawLine in const LineSplitter().convert(metadataRaw)) {
      final line = rawLine.replaceAll('\r', '');
      if (line.isEmpty) {
        flushActiveHeader();
        activeHeader = null;
        activeValue.clear();
        continue;
      }
      if ((line.startsWith(' ') || line.startsWith('\t')) &&
          activeHeader != null) {
        activeValue.write(' ');
        activeValue.write(line.trim());
        continue;
      }
      flushActiveHeader();
      activeHeader = null;
      activeValue.clear();
      final sepIndex = line.indexOf(':');
      if (sepIndex <= 0) continue;
      activeHeader = line.substring(0, sepIndex).trim();
      activeValue.write(line.substring(sepIndex + 1).trim());
    }
    flushActiveHeader();
    return output;
  }

  /// 规范化 `Requires-Dist` 到当前 requirement 语法子集。
  ///
  /// 示例：
  /// - `python-dateutil (>=2.8.2)` -> `python-dateutil>=2.8.2`
  /// - `pytz; python_version < "3.12"` -> `pytz`（marker 命中时）
  String? _normalizeRequiresDistRequirement(String requiresDistRaw) {
    final raw = requiresDistRaw.trim();
    if (raw.isEmpty) return null;
    final splitIndex = raw.indexOf(';');
    final requirementPart =
        splitIndex >= 0 ? raw.substring(0, splitIndex).trim() : raw;
    final markerPart = splitIndex >= 0 ? raw.substring(splitIndex + 1).trim() : '';
    if (markerPart.isNotEmpty && !_evaluateEnvironmentMarker(markerPart)) {
      return null;
    }

    final withoutExtras = requirementPart.replaceAll(
      RegExp(r'\[[^\]]+\]'),
      '',
    );
    final match = RegExp(
      r'^([A-Za-z0-9_.-]+)\s*(?:\(([^)]+)\)|([<>=!~].*))?$',
    ).firstMatch(withoutExtras.trim());
    if (match == null) {
      return null;
    }
    final packageName = (match.group(1) ?? '').trim().toLowerCase();
    if (packageName.isEmpty) return null;
    final rawSpec = (match.group(2) ?? match.group(3) ?? '').trim();
    if (rawSpec.isEmpty) {
      return packageName;
    }
    final normalizedTokens =
        rawSpec
            .split(',')
            .map(_normalizeRequirementConstraintToken)
            .where((item) => item.isNotEmpty)
            .toList();
    if (normalizedTokens.isEmpty) {
      return packageName;
    }
    return '$packageName${normalizedTokens.join(',')}';
  }

  /// 规范化单个版本约束 token。
  ///
  /// 说明：`~=` 在当前轻量实现中退化为下界约束 `>=`。
  String _normalizeRequirementConstraintToken(String tokenRaw) {
    final token = tokenRaw.trim().replaceAll(' ', '');
    if (token.isEmpty) return '';
    final match = RegExp(
      r'^(===|==|!=|~=|>=|<=|>|<)\s*([A-Za-z0-9_.+\-]+)$',
    ).firstMatch(token);
    if (match == null) return '';
    final operator = match.group(1)!;
    final version = match.group(2)!;
    if (operator == '~=') {
      return '>=$version';
    }
    if (operator == '===') {
      return '==$version';
    }
    return '$operator$version';
  }

  /// 评估 PEP 508 marker（简化实现）。
  ///
  /// 设计取舍：
  /// 1. 支持常用键：`python_version/sys_platform/platform_system/os_name/extra`。
  /// 2. 复杂表达式无法解析时返回 `true`，优先避免漏装必要依赖。
  bool _evaluateEnvironmentMarker(String markerExpression) {
    final normalized = markerExpression.trim();
    if (normalized.isEmpty) return true;
    final orParts = normalized.split(RegExp(r'\s+or\s+', caseSensitive: false));
    for (final orPart in orParts) {
      final andParts = orPart.split(RegExp(r'\s+and\s+', caseSensitive: false));
      var allMatched = true;
      for (final andPart in andParts) {
        if (!_evaluateMarkerCondition(andPart.trim())) {
          allMatched = false;
          break;
        }
      }
      if (allMatched) return true;
    }
    return false;
  }

  bool _evaluateMarkerCondition(String condition) {
    if (condition.isEmpty) return true;
    final extraMatch = RegExp(
      r'''^extra\s*(==|!=)\s*['"]?([a-z0-9_.-]+)['"]?$''',
      caseSensitive: false,
    ).firstMatch(condition);
    if (extraMatch != null) {
      // 当前场景无 extras 选择能力：extra==x 恒 false，extra!=x 恒 true。
      return extraMatch.group(1) == '!=';
    }
    final match = RegExp(
      r'''^(python_version|sys_platform|platform_system|os_name)\s*(==|!=|>=|<=|>|<)\s*['"]?([a-z0-9._-]+)['"]?$''',
      caseSensitive: false,
    ).firstMatch(condition);
    if (match == null) {
      return true;
    }
    final key = match.group(1)!.toLowerCase();
    final operator = match.group(2)!;
    final expected = match.group(3)!.toLowerCase();
    switch (key) {
      case 'python_version':
        return _compareByOperator(
          current: _runtimePythonVersion,
          expected: expected,
          operator: operator,
          isVersion: true,
        );
      case 'sys_platform':
        return _compareByOperator(
          current: _runtimeSysPlatform,
          expected: expected,
          operator: operator,
        );
      case 'platform_system':
        return _compareByOperator(
          current: _runtimePlatformSystem,
          expected: expected,
          operator: operator,
        );
      case 'os_name':
        return _compareByOperator(
          current: _runtimeOsName,
          expected: expected,
          operator: operator,
        );
    }
    return true;
  }

  bool _compareByOperator({
    required String current,
    required String expected,
    required String operator,
    bool isVersion = false,
  }) {
    final cmp =
        isVersion
            ? _compareVersionsLoose(current, expected)
            : current.compareTo(expected);
    switch (operator) {
      case '==':
        return cmp == 0;
      case '!=':
        return cmp != 0;
      case '>=':
        return cmp >= 0;
      case '<=':
        return cmp <= 0;
      case '>':
        return cmp > 0;
      case '<':
        return cmp < 0;
    }
    return true;
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

/// requirements 安装队列节点（包含来源，用于日志追踪）。
class _PendingRequirement {
  final String requirement;
  final String source;

  const _PendingRequirement({required this.requirement, required this.source});
}

/// 从 wheel metadata 解析出的传递依赖。
class _TransitiveRequirement {
  final String requirement;
  final String source;

  const _TransitiveRequirement({
    required this.requirement,
    required this.source,
  });
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
      final opMatch = RegExp(
        r'^(==|!=|~=|>=|<=|>|<)\s*([A-Za-z0-9_.+\-]+)$',
      ).firstMatch(token);
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
        case '!=':
          if (cmp == 0) return false;
          break;
        case '~=':
          // 轻量语义：`~=` 退化为 `>=` 下界匹配。
          if (cmp < 0) return false;
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
  final String sourceType;
  final String indexUrl;
  final int wheelScore;
  final DateTime? uploadedAt;

  const _ResolvedRequirementCandidate({
    required this.packageName,
    required this.requested,
    required this.version,
    required this.downloadUrl,
    required this.sha256,
    required this.mirrorId,
    required this.sourceType,
    required this.indexUrl,
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
