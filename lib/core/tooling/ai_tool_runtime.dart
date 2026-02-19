import 'dart:convert';

import 'package:now_chat/core/plugin/plugin_hook_bus.dart';
import 'package:now_chat/core/plugin/plugin_registry.dart';
import 'package:now_chat/core/plugin/plugin_runtime_executor.dart';
import 'package:now_chat/util/app_logger.dart';

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
    return tools
        .map((binding) {
          return <String, dynamic>{
            'type': 'function',
            'function': <String, dynamic>{
              'name': binding.tool.name,
              'description': binding.tool.description,
              'parameters': binding.tool.parametersSchema,
            },
          };
        })
        .toList(growable: false);
  }

  /// 执行单个工具调用。
  static Future<AIToolExecutionResult> execute(AIToolCall call) async {
    final started = DateTime.now();
    final binding = PluginRegistry.instance.resolveToolByName(call.name);
    if (binding == null) {
      AppLogger.w('ToolUsage SKIP unsupported tool=${call.name}');
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
    final argsForLog = _safeParseJsonObject(call.rawArguments);
    _logToolExecutionStart(
      call: call,
      pluginId: binding.plugin.id,
      runtime: binding.tool.runtime,
      args: argsForLog,
    );

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
      _logToolExecutionEnd(
        call: call,
        pluginId: binding.plugin.id,
        runtime: binding.tool.runtime,
        result: withDuration,
      );
      return withDuration;
    } catch (e, st) {
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
      _logToolExecutionFailure(
        call: call,
        pluginId: binding.plugin.id,
        runtime: binding.tool.runtime,
        error: e,
        stackTrace: st,
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
    final pluginResult = _decodeJsonObjectFromStdout(result.stdout);
    final ok =
        pluginResult == null
            ? result.isSuccess
            : (pluginResult['ok'] == true && result.isSuccess);
    final summaryFromPlugin = pluginResult?['summary']?.toString();
    final errorFromPlugin = pluginResult?['error']?.toString();

    // 插件可直接返回完整 JSON 对象作为工具结果；宿主会补齐缺省字段。
    final toolPayload = <String, dynamic>{
      if (pluginResult != null) ...pluginResult,
      'ok': ok,
      'stdout': stdout,
      'stderr': stderr,
      'exitCode': result.exitCode,
      'timedOut': result.timedOut,
      'durationMs': result.duration.inMilliseconds,
    };

    return AIToolExecutionResult(
      status: ok ? 'success' : 'error',
      summary:
          summaryFromPlugin ??
          'exit=${result.exitCode} · ${result.duration.inMilliseconds}ms${result.timedOut ? " · timeout" : ""}',
      toolMessageContent: jsonEncode(toolPayload),
      error:
          ok
              ? null
              : (errorFromPlugin ??
                  (stderr.trim().isEmpty ? 'plugin_runtime_failed' : stderr)),
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
    final value =
        raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
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

  /// 从 stdout 末尾提取 JSON 对象，允许脚本前面输出调试日志。
  static Map<String, dynamic>? _decodeJsonObjectFromStdout(String stdout) {
    final lines =
        stdout
            .split('\n')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList()
            .reversed;
    for (final line in lines) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {
        // 当前行不是 JSON，继续尝试上一行。
      }
    }
    return null;
  }

  /// 打印工具开始执行日志（含参数摘要）。
  static void _logToolExecutionStart({
    required AIToolCall call,
    required String pluginId,
    required String runtime,
    required Map<String, dynamic> args,
  }) {
    AppLogger.i(
      'ToolUsage START tool=${call.name} plugin=$pluginId runtime=$runtime args=${_summarizeArgsForLog(args)}',
    );
  }

  /// 打印工具完成日志（含状态、耗时与摘要）。
  static void _logToolExecutionEnd({
    required AIToolCall call,
    required String pluginId,
    required String runtime,
    required AIToolExecutionResult result,
  }) {
    final message =
        'ToolUsage END tool=${call.name} plugin=$pluginId runtime=$runtime status=${result.status} duration=${result.durationMs ?? 0}ms summary=${_truncateForLog(result.summary, 220)}';
    if (result.status == 'success') {
      AppLogger.i(message);
    } else {
      AppLogger.w(
        '$message error=${_truncateForLog(result.error ?? 'unknown', 220)}',
      );
    }
  }

  /// 打印工具异常日志（捕获未处理异常）。
  static void _logToolExecutionFailure({
    required AIToolCall call,
    required String pluginId,
    required String runtime,
    required Object error,
    StackTrace? stackTrace,
  }) {
    AppLogger.e(
      'ToolUsage EXCEPTION tool=${call.name} plugin=$pluginId runtime=$runtime',
      error,
      stackTrace,
    );
  }

  /// 生成参数摘要，避免日志被超长代码撑满。
  static String _summarizeArgsForLog(Map<String, dynamic> args) {
    if (args.isEmpty) return '{}';
    final summarized = <String, dynamic>{};
    for (final entry in args.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key == 'code') {
        final code = value?.toString() ?? '';
        summarized[key] =
            'chars=${code.length}, preview="${_truncateForLog(_singleLine(code), 120)}"';
        continue;
      }
      if (value is String) {
        summarized[key] = _truncateForLog(_singleLine(value), 120);
        continue;
      }
      summarized[key] = value;
    }
    try {
      return jsonEncode(summarized);
    } catch (_) {
      return summarized.toString();
    }
  }

  /// 压缩多行文本为单行，方便日志阅读。
  static String _singleLine(String text) {
    return text.replaceAll('\r', ' ').replaceAll('\n', ' ').trim();
  }

  /// 日志文本截断，避免过长输出影响排查效率。
  static String _truncateForLog(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
}
