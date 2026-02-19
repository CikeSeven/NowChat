import 'dart:convert';

import 'package:now_chat/core/models/python_execution_result.dart';
import 'package:now_chat/core/plugin/plugin_registry.dart';
import 'package:now_chat/core/plugin/python_plugin_service.dart';

/// 插件运行时执行器：统一执行插件声明的 runtime 处理器。
class PluginRuntimeExecutor {
  const PluginRuntimeExecutor._();
  static const String _pluginUiSchemaPath = 'ui/schema.py';

  /// 执行插件 runtime（当前支持 `python_inline` / `python_script` / `log`）。
  static Future<PythonExecutionResult> execute({
    required String pluginId,
    required String runtime,
    String? scriptPath,
    String? inlineCode,
    Map<String, dynamic>? payload,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final normalizedRuntime = runtime.trim().toLowerCase();
    if (normalizedRuntime == 'log') {
      return const PythonExecutionResult(
        stdout: 'log runtime executed',
        stderr: '',
        exitCode: 0,
        duration: Duration.zero,
        timedOut: false,
      );
    }

    final wrappedCode = _buildRuntimeCode(
      pluginId: pluginId,
      runtime: normalizedRuntime,
      scriptPath: scriptPath,
      inlineCode: inlineCode,
      payload: payload ?? const <String, dynamic>{},
    );
    final extraPaths = PluginRegistry.instance.resolvePythonPathsForPlugin(pluginId);
    final service = PythonPluginService();
    return service.executeCode(
      code: wrappedCode,
      timeout: timeout,
      extraSysPaths: extraPaths,
    );
  }

  /// 加载插件页面 DSL 定义并返回初始页面状态。
  static Future<Map<String, dynamic>> loadPluginUiPage({
    required String pluginId,
    Map<String, dynamic>? payload,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    return _executePluginUiDsl(
      pluginId: pluginId,
      payload: payload ?? const <String, dynamic>{},
      timeout: timeout,
    );
  }

  /// 分发插件页面事件，由 Python 返回下一帧 UI 状态。
  static Future<Map<String, dynamic>> dispatchPluginUiEvent({
    required String pluginId,
    required String eventType,
    required String componentId,
    dynamic value,
    Map<String, dynamic>? payload,
    Map<String, dynamic>? state,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    return _executePluginUiDsl(
      pluginId: pluginId,
      payload: payload ?? const <String, dynamic>{},
      timeout: timeout,
      eventType: eventType,
      componentId: componentId,
      value: value,
      state: state ?? const <String, dynamic>{},
    );
  }

  static String _buildRuntimeCode({
    required String pluginId,
    required String runtime,
    required String? scriptPath,
    required String? inlineCode,
    required Map<String, dynamic> payload,
  }) {
    final payloadJson = jsonEncode(payload);
    final payloadLiteral = jsonEncode(payloadJson);
    if (runtime == 'python_inline') {
      final code = (inlineCode ?? '').trim();
      if (code.isEmpty) {
        throw Exception('插件 runtime 缺少 inlineCode: $pluginId');
      }
      return '''
import json
payload = json.loads($payloadLiteral)
_result = None
$code
if _result is not None:
    print(json.dumps(_result, ensure_ascii=False))
''';
    }

    if (runtime == 'python_script') {
      final resolved = _resolveScriptPath(pluginId, scriptPath);
      final resolvedJson = jsonEncode(resolved);
      final resolvedLiteral = jsonEncode(resolvedJson);
      return '''
import json
payload = json.loads($payloadLiteral)
script_path = json.loads($resolvedLiteral)
_namespace = {"__file__": script_path}
with open(script_path, "r", encoding="utf-8") as _f:
    _source = _f.read()
exec(compile(_source, script_path, "exec"), _namespace)
_handler = _namespace.get("main") or _namespace.get("handle")
if callable(_handler):
    _result = _handler(payload)
    if _result is not None:
        print(json.dumps(_result, ensure_ascii=False))
''';
    }

    throw Exception('不支持的 runtime: $runtime');
  }

  static String _resolveScriptPath(String pluginId, String? scriptPath) {
    final normalized = (scriptPath ?? '').trim();
    if (normalized.isEmpty) {
      throw Exception('python_script 缺少 scriptPath: $pluginId');
    }
    final resolved = PluginRegistry.instance.resolvePluginFilePath(
      pluginId,
      normalized,
    );
    if (resolved == null) {
      throw Exception('找不到插件脚本: $pluginId/$normalized');
    }
    return resolved;
  }

  /// 运行插件 UI DSL 脚本并解析 JSON 结果。
  static Future<Map<String, dynamic>> _executePluginUiDsl({
    required String pluginId,
    required Map<String, dynamic> payload,
    required Duration timeout,
    String? eventType,
    String? componentId,
    dynamic value,
    Map<String, dynamic>? state,
  }) async {
    final schemaPath = _resolveScriptPath(pluginId, _pluginUiSchemaPath);
    final payloadLiteral = _toPythonJsonLiteral(payload);
    final eventTypeLiteral = _toPythonJsonLiteral(eventType);
    final componentIdLiteral = _toPythonJsonLiteral(componentId);
    final valueLiteral = _toPythonJsonLiteral(value);
    final stateLiteral = _toPythonJsonLiteral(state ?? const <String, dynamic>{});
    final schemaPathLiteral = _toPythonJsonLiteral(schemaPath);

    final code = '''
import json
payload = json.loads($payloadLiteral)
event_type = json.loads($eventTypeLiteral)
component_id = json.loads($componentIdLiteral)
value = json.loads($valueLiteral)
current_state = json.loads($stateLiteral)
schema_path = json.loads($schemaPathLiteral)

_namespace = {"__file__": schema_path}
with open(schema_path, "r", encoding="utf-8") as _f:
    _source = _f.read()
exec(compile(_source, schema_path, "exec"), _namespace)

_factory = _namespace.get("create_page")
if not callable(_factory):
    raise Exception("ui/schema.py 缺少 create_page()")

_page = _factory()
if event_type:
    _result = _page.on_event({
        "type": event_type,
        "componentId": component_id,
        "value": value,
        "state": current_state,
        "payload": payload,
    })
else:
    _result = _page.build({"payload": payload})

if _result is not None:
    print(json.dumps(_result, ensure_ascii=False))
''';

    final extraPaths = PluginRegistry.instance.resolvePythonPathsForPlugin(pluginId);
    final service = PythonPluginService();
    final result = await service.executeCode(
      code: code,
      timeout: timeout,
      extraSysPaths: extraPaths,
    );
    if (!result.isSuccess) {
      throw Exception(
        result.stderr.trim().isEmpty ? '插件 UI 执行失败' : result.stderr.trim(),
      );
    }
    return _decodeJsonObjectFromStdout(result.stdout);
  }

  /// 将 Dart 值编码成 Python 可安全 json.loads 的文本字面量。
  static String _toPythonJsonLiteral(dynamic value) {
    return jsonEncode(jsonEncode(value));
  }

  /// 从 stdout 末尾提取 JSON 对象，允许插件先输出调试日志。
  static Map<String, dynamic> _decodeJsonObjectFromStdout(String stdout) {
    final lines = stdout
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
          return decoded.map(
            (key, value) => MapEntry(key.toString(), value),
          );
        }
      } catch (_) {
        // 继续尝试上一行，允许日志中混入非 JSON 文本。
      }
    }
    throw const FormatException('插件 UI 返回格式错误：缺少 JSON 对象');
  }
}
