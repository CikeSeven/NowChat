import 'dart:async';
import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:http/http.dart' as http;
import 'package:isar/isar.dart';
import 'package:logger/web.dart';
import 'package:now_chat/core/models/message.dart';
import 'package:now_chat/util/app_logger.dart';

import '../models/ai_provider_config.dart';
import '../models/chat_session.dart';

part 'api_service_common.part.dart';
part 'api_service_streaming.part.dart';
part 'api_service_requests.part.dart';

/// 用户主动中断生成时抛出的受控异常。
class GenerationAbortedException implements Exception {
  final String message;

  const GenerationAbortedException([
    this.message = 'generation aborted by user',
  ]);

  @override
  String toString() => message;
}

/// 生成中断控制器，用于跨层传播停止信号。
class GenerationAbortController {
  bool _aborted = false;
  final List<void Function()> _listeners = <void Function()>[];

  bool get isAborted => _aborted;

  /// 注册中断监听器。若当前已中断，将立即触发。
  void onAbort(void Function() listener) {
    if (_aborted) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  /// 触发中断并通知监听器。
  void abort() {
    if (_aborted) return;
    _aborted = true;
    final snapshot = List<void Function()>.from(_listeners);
    _listeners.clear();
    for (final listener in snapshot) {
      listener();
    }
  }
}

/// API 服务统一入口。
///
/// 对外仅暴露少量稳定方法，内部实现按职责拆分到 part 文件。
class ApiService {
  /// 发送流式聊天请求。
  static Future<void> sendChatRequestStreaming({
    required AIProviderConfig provider,
    required ChatSession session,
    required Isar isar,
    GenerationAbortController? abortController,
    List<Message>? overrideMessages,
    FutureOr<void> Function(String deltaContent, String? deltaReasoning)?
    onStream,
    FutureOr<void> Function()? onDone,
  }) => _sendChatRequestStreamingInternal(
    provider: provider,
    session: session,
    isar: isar,
    abortController: abortController,
    overrideMessages: overrideMessages,
    onStream: onStream,
    onDone: onDone,
  );

  /// 发送非流式聊天请求。
  static Future<Map<String, dynamic>> sendChatRequest({
    required AIProviderConfig provider,
    required ChatSession session,
    required Isar isar,
    GenerationAbortController? abortController,
    List<Message>? overrideMessages,
  }) => _sendChatRequestInternal(
    provider: provider,
    session: session,
    isar: isar,
    abortController: abortController,
    overrideMessages: overrideMessages,
  );

  /// 获取模型列表。
  static Future<List<String>> fetchModels(
    AIProviderConfig provider,
    String baseUrl,
    String apiKey,
  ) => _fetchModelsInternal(provider, baseUrl, apiKey);
}
