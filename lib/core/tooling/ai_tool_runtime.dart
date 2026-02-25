import 'dart:convert';

import 'package:now_chat/core/image/image_generation_queue_bridge.dart';
import 'package:now_chat/core/image/image_tool_settings.dart';
import 'package:now_chat/core/models/ai_provider_config.dart';
import 'package:now_chat/core/models/image_generation_task.dart';
import 'package:now_chat/core/plugin/plugin_hook_bus.dart';
import 'package:now_chat/core/plugin/plugin_registry.dart';
import 'package:now_chat/core/plugin/plugin_runtime_executor.dart';
import 'package:now_chat/util/app_logger.dart';
import 'package:now_chat/util/storage.dart';

const int _defaultPythonTimeoutSeconds = 20;
const int _maxPythonTimeoutSeconds = 90;

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
///
/// 设计目标：
/// - 向模型暴露“当前可用工具”。
/// - 执行模型下发的 tool_call，并把结果回填为标准 JSON 文本。
/// - 全流程记录日志，便于在插件/模型/宿主三端快速定位问题。
class AIToolRuntime {
  const AIToolRuntime._();

  static const String _toolGenerateImage = 'generate_image';
  static const String _toolEditImage = 'edit_image';

  /// 构建 OpenAI `tools` 参数（基于插件开关与工具开关）。
  ///
  /// 返回值会直接放入聊天请求体，因此必须确保结构稳定且字段完整。
  static Future<List<Map<String, dynamic>>> buildOpenAIToolsSchema() async {
    final settings = await ImageToolSettingsStore.load();
    final tools = PluginRegistry.instance.resolveEnabledTools();
    final schemas =
        tools
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
        // 后续会按设置动态追加内置生图工具，因此必须使用可增长列表。
        .toList(growable: true);
    if (settings.exposeImageToolsToChat) {
      schemas.addAll(_buildBuiltinImageToolsSchema());
    }
    return schemas;
  }

  /// 执行单个工具调用。
  ///
  /// 执行链路：
  /// 1. 查找工具绑定（插件 + 工具定义）。
  /// 2. 触发 `tool_before_execute` Hook。
  /// 3. 按 runtime 执行。
  /// 4. 触发 `tool_after_execute` Hook。
  /// 5. 返回可回填给模型的工具结果。
  static Future<AIToolExecutionResult> execute(AIToolCall call) async {
    final started = DateTime.now();
    if (call.name == _toolGenerateImage || call.name == _toolEditImage) {
      final builtInResult = await _executeBuiltinImageTool(call, started);
      _logToolExecutionEnd(
        call: call,
        pluginId: 'builtin',
        runtime: 'builtin_image',
        result: builtInResult,
      );
      return builtInResult;
    }

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

      // 统一补齐耗时字段，避免不同 runtime 返回结构不一致。
      final withDuration = _withDuration(result, started);
      await PluginHookBus.emit(
        'tool_after_execute',
        payload: <String, dynamic>{
          'toolName': call.name,
          'pluginId': binding.plugin.id,
          'status': withDuration.status,
          'durationMs': withDuration.durationMs,
          'error': withDuration.error,
          // 透出工具执行返回值，供插件在 tool_after_execute 中记录日志。
          'summary': withDuration.summary,
          'toolMessageContent': withDuration.toolMessageContent,
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
      // 异常分支仍返回结构化结果给模型，避免 tool_call 阶段直接崩链路。
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
          // 异常分支也透出统一返回值，保证插件日志字段稳定。
          'summary': result.summary,
          'toolMessageContent': result.toolMessageContent,
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

  /// 构建内置图片工具 schema。
  static List<Map<String, dynamic>> _buildBuiltinImageToolsSchema() {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'function',
        'function': <String, dynamic>{
          'name': _toolGenerateImage,
          'description':
              '将“图片生成”任务加入生图队列（使用生图设置中的默认生图模型），'
                  '立即返回入队结果，不等待图片生成完成',
          'parameters': <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'prompt': <String, dynamic>{
                'type': 'string',
                'description': '生图提示词',
              },
            },
            'required': ['prompt'],
          },
        },
      },
      <String, dynamic>{
        'type': 'function',
        'function': <String, dynamic>{
          'name': _toolEditImage,
          'description':
              '将“图片编辑”任务加入生图队列（使用生图设置中的默认图片编辑模型），'
                  '立即返回入队结果，不等待图片生成完成',
          'parameters': <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'prompt': <String, dynamic>{
                'type': 'string',
                'description': '图片编辑指令',
              },
              'image_path': <String, dynamic>{
                'type': 'string',
                'description': '待编辑图片的本地绝对路径',
              },
            },
            'required': ['prompt', 'image_path'],
          },
        },
      },
    ];
  }

  /// 执行内置图片工具（生图/图片编辑）。
  static Future<AIToolExecutionResult> _executeBuiltinImageTool(
    AIToolCall call,
    DateTime started,
  ) async {
    try {
      final args = _safeParseJsonObject(call.rawArguments);
      final settings = await ImageToolSettingsStore.load();
      if (!settings.exposeImageToolsToChat) {
        return _withDuration(
          AIToolExecutionResult(
            status: 'error',
            summary: '生图工具未开启',
            toolMessageContent: jsonEncode(<String, dynamic>{
              'ok': false,
              'error': 'image tools disabled',
            }),
            error: 'image tools disabled',
          ),
          started,
        );
      }
      final providers = await Storage.loadProviders();
      final isGenerate = call.name == _toolGenerateImage;
      final targetProviderId =
          isGenerate ? settings.generationProviderId : settings.editProviderId;
      final targetModel = isGenerate ? settings.generationModel : settings.editModel;
      if (targetProviderId == null || targetModel == null) {
        return _withDuration(
          AIToolExecutionResult(
            status: 'error',
            summary: '未配置默认${isGenerate ? '生图' : '图片编辑'}模型',
            toolMessageContent: jsonEncode(<String, dynamic>{
              'ok': false,
              'error': 'default image model not configured',
            }),
            error: 'default image model not configured',
          ),
          started,
        );
      }

      AIProviderConfig? provider;
      for (final item in providers) {
        if (item.id == targetProviderId) {
          provider = item;
          break;
        }
      }
      if (provider == null) {
        return _withDuration(
          AIToolExecutionResult(
            status: 'error',
            summary: '默认图片模型对应的 Provider 不存在',
            toolMessageContent: jsonEncode(<String, dynamic>{
              'ok': false,
              'error': 'provider not found',
            }),
            error: 'provider not found',
          ),
          started,
        );
      }

      final modelFeatures = provider.featuresForModel(targetModel);
      final prompt = (args['prompt'] ?? '').toString().trim();
      if (prompt.isEmpty) {
        return _withDuration(
          AIToolExecutionResult(
            status: 'error',
            summary: '参数缺失：prompt',
            toolMessageContent: jsonEncode(<String, dynamic>{
              'ok': false,
              'error': 'missing prompt',
            }),
            error: 'missing prompt',
          ),
          started,
        );
      }

      // 对聊天工具调用，尺寸统一跟随生图设置页，避免模型携带旧 size 导致配置不生效。
      final sizeFromSettings = settings.generationSize;
      late final ImageGenerationTask task;
      if (isGenerate) {
        if (modelFeatures.modelType != ModelType.imageGeneration) {
          return _withDuration(
            AIToolExecutionResult(
              status: 'error',
              summary: '默认生图模型类型不正确',
              toolMessageContent: jsonEncode(<String, dynamic>{
                'ok': false,
                'error': 'default model is not image-generation model',
              }),
              error: 'default model is not image-generation model',
            ),
            started,
          );
        }
        task = ImageGenerationTask.createQueued(
          mode: ImageGenerationTaskMode.generate,
          providerId: provider.id,
          model: targetModel,
          requestMode: modelFeatures.imageRequestMode,
          prompt: prompt,
          size: sizeFromSettings,
          requestCount: settings.generationCount,
        );
      } else {
        if (modelFeatures.modelType != ModelType.imageEdit) {
          return _withDuration(
            AIToolExecutionResult(
              status: 'error',
              summary: '默认图片编辑模型类型不正确',
              toolMessageContent: jsonEncode(<String, dynamic>{
                'ok': false,
                'error': 'default model is not image-edit model',
              }),
              error: 'default model is not image-edit model',
            ),
            started,
          );
        }
        final imagePath = (args['image_path'] ?? '').toString().trim();
        if (imagePath.isEmpty) {
          return _withDuration(
            AIToolExecutionResult(
              status: 'error',
              summary: '参数缺失：image_path',
              toolMessageContent: jsonEncode(<String, dynamic>{
                'ok': false,
                'error': 'missing image_path',
              }),
              error: 'missing image_path',
            ),
            started,
          );
        }
        task = ImageGenerationTask.createQueued(
          mode: ImageGenerationTaskMode.edit,
          providerId: provider.id,
          model: targetModel,
          requestMode: modelFeatures.imageRequestMode,
          prompt: prompt,
          sourceImagePath: imagePath,
          size: sizeFromSettings,
        );
      }

      await ImageGenerationQueueBridge.enqueueTask(task);
      final payload = <String, dynamic>{
        'ok': true,
        'queued': true,
        'tool': call.name,
        'taskId': task.id,
        'taskStatus': task.status.name,
        'mode': task.mode.name,
        'providerId': provider.id,
        'model': targetModel,
        'size': task.size,
        'requestCount': task.requestCount,
        'message': '任务已加入生图队列，请稍后在工作台查看结果',
      };
      return _withDuration(
        AIToolExecutionResult(
          status: 'success',
          summary: '${call.name} 入队成功，task=${task.id}',
          toolMessageContent: jsonEncode(payload),
          error: null,
        ),
        started,
      );
    } catch (error, stackTrace) {
      AppLogger.e('内置图片工具执行失败', error, stackTrace);
      return _withDuration(
        AIToolExecutionResult(
          status: 'error',
          summary: '${call.name} 执行失败: $error',
          toolMessageContent: jsonEncode(<String, dynamic>{
            'ok': false,
            'error': error.toString(),
          }),
          error: error.toString(),
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

  /// 插件声明 runtime 的 Python 执行器。
  ///
  /// 约定：
  /// - 插件可在 stdout 末尾输出 JSON 作为结构化返回。
  /// - 宿主会把 stdout/stderr/exitCode 等诊断字段补回 tool payload。
  static Future<AIToolExecutionResult> _execPluginRuntimePython({
    required String pluginId,
    required String runtime,
    required String rawArgs,
    required String? scriptPath,
    required String? inlineCode,
    required int timeoutSec,
  }) async {
    // 参数解析失败时回退为空对象，防止模型偶发 JSON 错误直接中断流程。
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

    // 保留完整 stdout/stderr，便于插件与宿主日志排查问题。
    final stdout = result.stdout;
    final stderr = result.stderr;
    final pluginResult = _decodeJsonObjectFromStdout(result.stdout);
    final ok =
        pluginResult == null
            ? result.isSuccess
            : (pluginResult['ok'] == true && result.isSuccess);
    final summaryFromPlugin = pluginResult?['summary']?.toString();
    final errorFromPlugin = pluginResult?['error']?.toString();

    // 插件可直接返回完整 JSON 对象作为工具结果；宿主会补齐缺省字段。
    // 面向模型的统一回包：无论插件是否返回 JSON，都具备基础诊断字段。
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
        'ToolUsage END tool=${call.name} plugin=$pluginId runtime=$runtime status=${result.status} duration=${result.durationMs ?? 0}ms summary=${result.summary}';
    if (result.status == 'success') {
      AppLogger.i(message);
    } else {
      AppLogger.w('$message error=${result.error ?? 'unknown'}');
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
