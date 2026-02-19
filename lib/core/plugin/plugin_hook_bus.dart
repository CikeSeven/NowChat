import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:now_chat/core/plugin/plugin_registry.dart';
import 'package:now_chat/core/plugin/plugin_runtime_executor.dart';
import 'package:now_chat/util/app_logger.dart';

/// Hook 执行日志项。
class PluginHookLogEntry {
  final DateTime time;
  final String pluginId;
  final String event;
  final bool ok;
  final String message;

  const PluginHookLogEntry({
    required this.time,
    required this.pluginId,
    required this.event,
    required this.ok,
    required this.message,
  });
}

/// 单次 Hook 分发结果，供业务层按需消费脚本输出。
class PluginHookEmitResult {
  /// 触发该结果的插件 ID。
  final String pluginId;

  /// 触发的 Hook 事件名。
  final String event;

  /// 运行是否成功（exit code=0 且未超时）。
  final bool ok;

  /// Hook 脚本解析出的 JSON 对象（若无有效 JSON 则为 null）。
  final Map<String, dynamic>? data;

  /// 运行标准输出（原始文本）。
  final String stdout;

  /// 运行错误输出（原始文本）。
  final String stderr;

  const PluginHookEmitResult({
    required this.pluginId,
    required this.event,
    required this.ok,
    required this.data,
    required this.stdout,
    required this.stderr,
  });
}

/// 插件 Hook 事件总线（白名单 + 失败隔离）。
class PluginHookBus {
  PluginHookBus._();

  static const Set<String> _whitelistEvents = <String>{
    'app_start',
    'app_resume',
    'page_enter',
    'page_leave',
    'chat_before_send',
    'chat_after_send',
    'tool_before_execute',
    'tool_after_execute',
  };

  static final List<PluginHookLogEntry> _logs = <PluginHookLogEntry>[];

  /// 读取最近 Hook 日志。
  static List<PluginHookLogEntry> get logs => List<PluginHookLogEntry>.from(_logs);

  /// 分发 Hook 事件到已启用插件，并返回每个 Hook 的执行结果。
  static Future<List<PluginHookEmitResult>> emit(
    String event, {
    Map<String, dynamic>? payload,
  }) async {
    final normalizedEvent = event.trim();
    if (!_whitelistEvents.contains(normalizedEvent)) {
      return const <PluginHookEmitResult>[];
    }
    final hooks = PluginRegistry.instance.resolveHooksByEvent(normalizedEvent);
    if (hooks.isEmpty) return const <PluginHookEmitResult>[];

    final contextPayload = <String, dynamic>{
      'event': normalizedEvent,
      'payload': payload ?? const <String, dynamic>{},
      'timestamp': DateTime.now().toIso8601String(),
    };
    final outputs = <PluginHookEmitResult>[];

    for (final item in hooks) {
      final plugin = item.$1;
      final hook = item.$2;
      try {
        final result = await PluginRuntimeExecutor.execute(
          pluginId: plugin.id,
          runtime: hook.runtime,
          scriptPath: hook.scriptPath,
          inlineCode: hook.inlineCode,
          payload: contextPayload,
          timeout: const Duration(seconds: 20),
        );
        final parsedData = result.isSuccess
            ? _decodeJsonObjectFromStdout(result.stdout)
            : null;
        _appendLog(
          PluginHookLogEntry(
            time: DateTime.now(),
            pluginId: plugin.id,
            event: normalizedEvent,
            ok: result.isSuccess,
            message: result.isSuccess
                ? (result.stdout.trim().isEmpty ? 'ok' : result.stdout.trim())
                : (result.stderr.trim().isEmpty ? 'failed' : result.stderr.trim()),
          ),
        );
        outputs.add(
          PluginHookEmitResult(
            pluginId: plugin.id,
            event: normalizedEvent,
            ok: result.isSuccess,
            data: parsedData,
            stdout: result.stdout,
            stderr: result.stderr,
          ),
        );
      } catch (e, st) {
        final message = 'hook 执行失败: $e';
        AppLogger.e(
          'Plugin hook error(plugin=${plugin.id}, event=$normalizedEvent)',
          e,
          st,
        );
        _appendLog(
          PluginHookLogEntry(
            time: DateTime.now(),
            pluginId: plugin.id,
            event: normalizedEvent,
            ok: false,
            message: message,
          ),
        );
        outputs.add(
          PluginHookEmitResult(
            pluginId: plugin.id,
            event: normalizedEvent,
            ok: false,
            data: null,
            stdout: '',
            stderr: e.toString(),
          ),
        );
      }
    }
    return outputs;
  }

  static void _appendLog(PluginHookLogEntry entry) {
    _logs.add(entry);
    if (_logs.length > 200) {
      _logs.removeRange(0, _logs.length - 200);
    }
    AppLogger.i(
      'PluginHook(${entry.pluginId}/${entry.event}): ${entry.ok ? "OK" : "ERR"} ${entry.message}',
    );
  }

  /// 尝试从 stdout 末尾提取 JSON 对象，允许脚本混入调试日志。
  static Map<String, dynamic>? _decodeJsonObjectFromStdout(String stdout) {
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
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {
        // 当前行不是 JSON，继续尝试上一行。
      }
    }
    return null;
  }
}

/// 导航观察者：将页面切换映射为 `page_enter/page_leave` Hook 事件。
class PluginHookNavigatorObserver extends NavigatorObserver {
  void _emitEnter(Route<dynamic>? route) {
    if (route == null) return;
    final name = route.settings.name ?? route.runtimeType.toString();
    PluginHookBus.emit('page_enter', payload: <String, dynamic>{'route': name});
  }

  void _emitLeave(Route<dynamic>? route) {
    if (route == null) return;
    final name = route.settings.name ?? route.runtimeType.toString();
    PluginHookBus.emit('page_leave', payload: <String, dynamic>{'route': name});
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _emitLeave(previousRoute);
    _emitEnter(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _emitLeave(route);
    _emitEnter(previousRoute);
    super.didPop(route, previousRoute);
  }
}

/// Hook 日志格式化工具。
String formatPluginHookLog(PluginHookLogEntry entry) {
  final time = entry.time.toIso8601String();
  final payload = <String, dynamic>{
    'time': time,
    'pluginId': entry.pluginId,
    'event': entry.event,
    'ok': entry.ok,
    'message': entry.message,
  };
  return jsonEncode(payload);
}
