import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:now_chat/core/plugin/plugin_hook_bus.dart';
import 'package:now_chat/core/plugin/plugin_registry.dart';
import 'package:now_chat/core/plugin/plugin_runtime_executor.dart';
import 'package:now_chat/core/plugin/python_plugin_service.dart';

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

/// 工具运行时：从插件注册表动态构建与执行工具。
class AIToolRuntime {
  const AIToolRuntime._();

  /// 构建 OpenAI `tools` 参数（基于插件开关与工具开关）。
  static List<Map<String, dynamic>> buildOpenAIToolsSchema() {
    final tools = PluginRegistry.instance.resolveEnabledTools();
    if (tools.isEmpty) return const <Map<String, dynamic>>[];
    return tools.map((binding) {
      return <String, dynamic>{
        'type': 'function',
        'function': <String, dynamic>{
          'name': binding.tool.name,
          'description': binding.tool.description,
          'parameters': binding.tool.parametersSchema,
        },
      };
    }).toList(growable: false);
  }

  /// 执行单个工具调用。
  static Future<AIToolExecutionResult> execute(AIToolCall call) async {
    final started = DateTime.now();
    final binding = PluginRegistry.instance.resolveToolByName(call.name);
    if (binding == null) {
      return AIToolExecutionResult(
        status: 'error',
        summary: '不支持的工具：${call.name}',
        toolMessageContent: jsonEncode(<String, dynamic>{
          'ok': false,
          'error': 'unsupported tool: ${call.name}',
        }),
        error: 'unsupported tool',
      );
    }

    await PluginHookBus.emit(
      'tool_before_execute',
      payload: <String, dynamic>{
        'toolName': call.name,
        'pluginId': binding.plugin.id,
      },
    );

    try {
      late AIToolExecutionResult result;
      switch (binding.tool.runtime.trim().toLowerCase()) {
        case 'builtin_web_fetch':
          result = await _execWebFetch(
            pluginId: binding.plugin.id,
            rawArgs: call.rawArguments,
            outputLimit: binding.tool.outputLimit,
          );
          break;
        case 'builtin_python_exec':
          result = await _execBuiltinPython(
            pluginId: binding.plugin.id,
            rawArgs: call.rawArguments,
            timeoutFallbackSec: binding.tool.timeoutSec,
            outputLimit: binding.tool.outputLimit,
          );
          break;
        case 'python_inline':
        case 'python_script':
          result = await _execPluginRuntimePython(
            pluginId: binding.plugin.id,
            runtime: binding.tool.runtime,
            rawArgs: call.rawArguments,
            scriptPath: binding.tool.scriptPath,
            inlineCode: binding.tool.inlineCode,
            timeoutSec: binding.tool.timeoutSec,
            outputLimit: binding.tool.outputLimit,
          );
          break;
        default:
          result = AIToolExecutionResult(
            status: 'error',
            summary: '未支持的工具 runtime: ${binding.tool.runtime}',
            toolMessageContent: jsonEncode(<String, dynamic>{
              'ok': false,
              'error': 'unsupported runtime: ${binding.tool.runtime}',
            }),
            error: 'unsupported runtime',
          );
      }

      final withDuration = _withDuration(result, started);
      await PluginHookBus.emit(
        'tool_after_execute',
        payload: <String, dynamic>{
          'toolName': call.name,
          'pluginId': binding.plugin.id,
          'status': withDuration.status,
          'durationMs': withDuration.durationMs,
          'error': withDuration.error,
        },
      );
      return withDuration;
    } catch (e) {
      final result = _withDuration(
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
      await PluginHookBus.emit(
        'tool_after_execute',
        payload: <String, dynamic>{
          'toolName': call.name,
          'pluginId': binding.plugin.id,
          'status': result.status,
          'durationMs': result.durationMs,
          'error': result.error,
        },
      );
      return result;
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

  /// 内置工具：网页抓取。
  static Future<AIToolExecutionResult> _execWebFetch({
    required String pluginId,
    required String rawArgs,
    required int outputLimit,
  }) async {
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
    final clipped = _truncateText(
      body.length <= maxChars ? body : body.substring(0, maxChars),
      outputLimit <= 0 ? _maxToolOutputChars : outputLimit,
    );
    final summary =
        'HTTP ${response.statusCode} · ${uri.host} · ${clipped.length} chars';
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    return AIToolExecutionResult(
      status: ok ? 'success' : 'error',
      summary: summary,
      toolMessageContent: jsonEncode(<String, dynamic>{
        'ok': ok,
        'status': response.statusCode,
        'url': uri.toString(),
        'content': clipped,
        'pluginId': pluginId,
      }),
      error: ok ? null : 'HTTP ${response.statusCode}',
    );
  }

  /// 内置工具：执行 Python 代码（参数 `code` / `timeout_sec`）。
  static Future<AIToolExecutionResult> _execBuiltinPython({
    required String pluginId,
    required String rawArgs,
    required int timeoutFallbackSec,
    required int outputLimit,
  }) async {
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
      fallback: timeoutFallbackSec <= 0
          ? _defaultPythonTimeoutSeconds
          : timeoutFallbackSec,
      min: 1,
      max: _maxPythonTimeoutSeconds,
    );
    final extraPaths = PluginRegistry.instance.resolvePythonPathsForPlugin(pluginId);
    final service = PythonPluginService();
    final result = await service.executeCode(
      code: code,
      timeout: Duration(seconds: timeoutSec),
      extraSysPaths: extraPaths,
    );
    final stdout = _truncateText(
      result.stdout,
      outputLimit <= 0 ? _maxToolOutputChars : outputLimit,
    );
    final stderr = _truncateText(
      result.stderr,
      outputLimit <= 0 ? _maxToolOutputChars : outputLimit,
    );
    final ok = !result.timedOut && result.exitCode == 0;
    return AIToolExecutionResult(
      status: ok ? 'success' : 'error',
      summary:
          'exit=${result.exitCode} · ${result.duration.inMilliseconds}ms${result.timedOut ? " · timeout" : ""}',
      toolMessageContent: jsonEncode(<String, dynamic>{
        'ok': ok,
        'exitCode': result.exitCode,
        'timedOut': result.timedOut,
        'durationMs': result.duration.inMilliseconds,
        'stdout': stdout,
        'stderr': stderr,
      }),
      error: ok ? null : (stderr.trim().isEmpty ? 'python_exec_failed' : stderr),
    );
  }

  /// 插件声明 runtime 的 Python 执行器。
  static Future<AIToolExecutionResult> _execPluginRuntimePython({
    required String pluginId,
    required String runtime,
    required String rawArgs,
    required String? scriptPath,
    required String? inlineCode,
    required int timeoutSec,
    required int outputLimit,
  }) async {
    final args = _safeParseJsonObject(rawArgs);
    final result = await PluginRuntimeExecutor.execute(
      pluginId: pluginId,
      runtime: runtime,
      scriptPath: scriptPath,
      inlineCode: inlineCode,
      payload: args,
      timeout: Duration(
        seconds: _toBoundedInt(
          timeoutSec,
          fallback: _defaultPythonTimeoutSeconds,
          min: 1,
          max: _maxPythonTimeoutSeconds,
        ),
      ),
    );

    final stdout = _truncateText(
      result.stdout,
      outputLimit <= 0 ? _maxToolOutputChars : outputLimit,
    );
    final stderr = _truncateText(
      result.stderr,
      outputLimit <= 0 ? _maxToolOutputChars : outputLimit,
    );
    final ok = result.isSuccess;

    return AIToolExecutionResult(
      status: ok ? 'success' : 'error',
      summary:
          'exit=${result.exitCode} · ${result.duration.inMilliseconds}ms${result.timedOut ? " · timeout" : ""}',
      toolMessageContent: jsonEncode(<String, dynamic>{
        'ok': ok,
        'stdout': stdout,
        'stderr': stderr,
        'exitCode': result.exitCode,
        'timedOut': result.timedOut,
        'durationMs': result.duration.inMilliseconds,
      }),
      error: ok ? null : (stderr.trim().isEmpty ? 'plugin_runtime_failed' : stderr),
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
        return decoded.map((key, value) => MapEntry(key.toString(), value));
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
    final value = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
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
}
