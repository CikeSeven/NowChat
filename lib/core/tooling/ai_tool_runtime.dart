import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:now_chat/core/models/python_plugin_manifest.dart';
import 'package:now_chat/core/plugin/python_plugin_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// OpenAI 工具调用名称：网页抓取。
const String kWebFetchToolName = 'web_fetch';

/// OpenAI 工具调用名称：执行 Python 代码。
const String kPythonExecToolName = 'python_exec';

const int _defaultWebFetchMaxChars = 8000;
const int _defaultPythonTimeoutSeconds = 20;
const int _maxPythonTimeoutSeconds = 90;
const int _maxToolOutputChars = 12000;

/// OpenAI tool_calls 的标准化结构。
class AIToolCall {
  /// 工具调用唯一标识（由模型生成）。
  final String id;

  /// 工具名称。
  final String name;

  /// 原始 JSON 参数字符串。
  final String rawArguments;

  const AIToolCall({
    required this.id,
    required this.name,
    required this.rawArguments,
  });
}

/// 单次工具执行结果。
class AIToolExecutionResult {
  /// 执行状态：`success` / `error` / `skipped`。
  final String status;

  /// 面向 UI 展示的简要结果。
  final String summary;

  /// 回填给模型的工具结果文本（JSON 字符串）。
  final String toolMessageContent;

  /// 执行耗时（毫秒）。
  final int? durationMs;

  /// 可选错误信息。
  final String? error;

  const AIToolExecutionResult({
    required this.status,
    required this.summary,
    required this.toolMessageContent,
    this.durationMs,
    this.error,
  });
}

/// 工具运行时：负责执行内置工具并返回结构化结果。
class AIToolRuntime {
  const AIToolRuntime._();

  /// 构建 OpenAI `tools` 参数。
  static List<Map<String, dynamic>> buildOpenAIToolsSchema() {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'function',
        'function': <String, dynamic>{
          'name': kWebFetchToolName,
          'description': '通过 HTTP GET 抓取网页文本内容，适合提取公开页面信息。',
          'parameters': <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'url': <String, dynamic>{
                'type': 'string',
                'description': '要抓取的完整 URL（仅支持 http/https）',
              },
              'max_chars': <String, dynamic>{
                'type': 'integer',
                'description': '返回内容最大字符数，默认 8000',
                'minimum': 200,
                'maximum': 30000,
              },
            },
            'required': <String>['url'],
          },
        },
      },
      <String, dynamic>{
        'type': 'function',
        'function': <String, dynamic>{
          'name': kPythonExecToolName,
          'description': '执行一段 Python 代码并返回 stdout/stderr。',
          'parameters': <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'code': <String, dynamic>{
                'type': 'string',
                'description': '要执行的 Python 代码',
              },
              'timeout_sec': <String, dynamic>{
                'type': 'integer',
                'description': '超时时间（秒），默认 20，最大 90',
                'minimum': 1,
                'maximum': 90,
              },
            },
            'required': <String>['code'],
          },
        },
      },
    ];
  }

  /// 执行单个工具调用。
  static Future<AIToolExecutionResult> execute(AIToolCall call) async {
    final started = DateTime.now();
    try {
      switch (call.name) {
        case kWebFetchToolName:
          return _withDuration(await _execWebFetch(call.rawArguments), started);
        case kPythonExecToolName:
          return _withDuration(await _execPython(call.rawArguments), started);
        default:
          return _withDuration(
            AIToolExecutionResult(
              status: 'error',
              summary: '不支持的工具：${call.name}',
              toolMessageContent: jsonEncode(<String, dynamic>{
                'ok': false,
                'error': 'unsupported tool: ${call.name}',
              }),
              error: 'unsupported tool',
            ),
            started,
          );
      }
    } catch (e) {
      return _withDuration(
        AIToolExecutionResult(
          status: 'error',
          summary: '执行异常: $e',
          toolMessageContent: jsonEncode(<String, dynamic>{
            'ok': false,
            'error': e.toString(),
          }),
          error: e.toString(),
        ),
        started,
      );
    }
  }

  static AIToolExecutionResult _withDuration(
    AIToolExecutionResult result,
    DateTime startedAt,
  ) {
    final durationMs = DateTime.now().difference(startedAt).inMilliseconds;
    return AIToolExecutionResult(
      status: result.status,
      summary: result.summary,
      toolMessageContent: result.toolMessageContent,
      error: result.error,
      durationMs: durationMs,
    );
  }

  /// 执行网页抓取工具。
  static Future<AIToolExecutionResult> _execWebFetch(String rawArgs) async {
    final args = _safeParseJsonObject(rawArgs);
    final url = (args['url'] ?? '').toString().trim();
    if (url.isEmpty) {
      return AIToolExecutionResult(
        status: 'error',
        summary: '缺少 url 参数',
        toolMessageContent: jsonEncode(<String, dynamic>{
          'ok': false,
          'error': 'missing url',
        }),
        error: 'missing url',
      );
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return AIToolExecutionResult(
        status: 'error',
        summary: 'URL 非法，仅支持 http/https',
        toolMessageContent: jsonEncode(<String, dynamic>{
          'ok': false,
          'error': 'invalid url',
        }),
        error: 'invalid url',
      );
    }

    final maxChars = _toBoundedInt(
      args['max_chars'],
      fallback: _defaultWebFetchMaxChars,
      min: 200,
      max: 30000,
    );
    final response = await http
        .get(uri, headers: <String, String>{'User-Agent': 'NowChat/1.0'})
        .timeout(const Duration(seconds: 20));

    final body = response.body;
    final clipped =
        body.length <= maxChars ? body : '${body.substring(0, maxChars)}\n...(已截断)';
    final summary =
        'HTTP ${response.statusCode} · ${uri.host} · ${clipped.length} chars';

    return AIToolExecutionResult(
      status: response.statusCode >= 200 && response.statusCode < 300
          ? 'success'
          : 'error',
      summary: summary,
      toolMessageContent: jsonEncode(<String, dynamic>{
        'ok': response.statusCode >= 200 && response.statusCode < 300,
        'status': response.statusCode,
        'url': uri.toString(),
        'content': clipped,
      }),
      error: response.statusCode >= 200 && response.statusCode < 300
          ? null
          : 'HTTP ${response.statusCode}',
    );
  }

  /// 执行 Python 代码工具。
  static Future<AIToolExecutionResult> _execPython(String rawArgs) async {
    final args = _safeParseJsonObject(rawArgs);
    final code = (args['code'] ?? '').toString();
    if (code.trim().isEmpty) {
      return AIToolExecutionResult(
        status: 'error',
        summary: '缺少 code 参数',
        toolMessageContent: jsonEncode(<String, dynamic>{
          'ok': false,
          'error': 'missing code',
        }),
        error: 'missing code',
      );
    }

    final timeoutSec = _toBoundedInt(
      args['timeout_sec'],
      fallback: _defaultPythonTimeoutSeconds,
      min: 1,
      max: _maxPythonTimeoutSeconds,
    );

    final extraSysPaths = await _resolveInstalledPythonPaths();
    final service = PythonPluginService();
    final result = await service.executeCode(
      code: code,
      timeout: Duration(seconds: timeoutSec),
      extraSysPaths: extraSysPaths,
    );

    final stdout = _truncateText(result.stdout, _maxToolOutputChars);
    final stderr = _truncateText(result.stderr, _maxToolOutputChars);
    final ok = !result.timedOut && result.exitCode == 0;
    final summary =
        'exit=${result.exitCode} · ${result.duration.inMilliseconds}ms${result.timedOut ? " · timeout" : ""}';

    return AIToolExecutionResult(
      status: ok ? 'success' : 'error',
      summary: summary,
      toolMessageContent: jsonEncode(<String, dynamic>{
        'ok': ok,
        'exitCode': result.exitCode,
        'timedOut': result.timedOut,
        'durationMs': result.duration.inMilliseconds,
        'stdout': stdout,
        'stderr': stderr,
      }),
      error: ok ? null : stderr.trim().isEmpty ? 'python_exec_failed' : stderr,
    );
  }

  /// 解析工具参数，异常时回退为空对象，避免抛错中断主流程。
  static Map<String, dynamic> _safeParseJsonObject(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {
      // 忽略并走空参数兜底。
    }
    return <String, dynamic>{};
  }

  /// 将动态输入转成指定范围内整数，用于限制工具参数上限。
  static int _toBoundedInt(
    dynamic raw, {
    required int fallback,
    required int min,
    required int max,
  }) {
    final value = raw is num
        ? raw.toInt()
        : int.tryParse(raw?.toString() ?? '');
    if (value == null) return fallback;
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  /// 裁剪过长输出，防止工具结果撑爆请求体与消息渲染。
  static String _truncateText(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars)}\n...(已截断)';
  }

  /// 从已安装插件记录中解析 Python 额外搜索路径（含原生库目录）。
  static Future<List<String>> _resolveInstalledPythonPaths() async {
    if (!Platform.isAndroid) return const <String>[];

    final supportDir = await getApplicationSupportDirectory();
    final pluginRoot = Directory(p.join(supportDir.path, 'python_plugin'));
    if (!pluginRoot.existsSync()) return const <String>[];

    const installedLibrariesKey = 'python_plugin_installed_libraries';
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(installedLibrariesKey) ?? '';
    if (raw.trim().isEmpty) return const <String>[];

    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <String>[];

    final paths = <String>[];
    final seen = <String>{};
    for (final item in decoded) {
      if (item is! Map) continue;
      final library = InstalledPythonLibrary.fromJson(
        Map<String, dynamic>.from(item),
      );
      final baseDir = p.normalize(p.join(pluginRoot.path, library.targetDir));

      for (final relativeEntry in library.pythonPathEntries) {
        final path = p.normalize(p.join(baseDir, relativeEntry));
        if (seen.add(path)) {
          paths.add(path);
        }
      }

      final nativeCandidates = <String>[
        p.normalize(p.join(baseDir, 'chaquopy', 'lib')),
        p.normalize(p.join(baseDir, 'lib')),
        p.normalize(p.join(baseDir, 'libs')),
      ];
      for (final candidate in nativeCandidates) {
        if (!Directory(candidate).existsSync()) continue;
        if (seen.add(candidate)) {
          paths.add(candidate);
        }
      }
    }
    return paths;
  }
}
