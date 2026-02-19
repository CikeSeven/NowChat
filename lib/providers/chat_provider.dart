import 'dart:async';

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:logger/web.dart';
import 'package:now_chat/core/models/ai_provider_config.dart';
import 'package:now_chat/core/models/tool_execution_log.dart';
import 'package:now_chat/core/network/api_service.dart';
import 'package:now_chat/util/app_logger.dart';

import '../core/models/chat_session.dart';
import '../core/models/message.dart';
import '../util/storage.dart';

part 'chat_provider/chat_provider_generation.part.dart';
part 'chat_provider/chat_provider_history.part.dart';
part 'chat_provider/chat_provider_message_store.part.dart';
part 'chat_provider/chat_provider_provider_ops.part.dart';

/// 记录某会话最后一条可继续生成的助手消息锚点。
class _PendingContinuation {
  final int assistantMessageId;
  final int anchorUserMessageId;

  const _PendingContinuation({
    required this.assistantMessageId,
    required this.anchorUserMessageId,
  });
}

/// 会话、消息与提供方的统一状态管理。
class ChatProvider with ChangeNotifier {
  static const int _defaultMessagePageSize = 50;
  static const Duration _streamingUiThrottle = Duration(milliseconds: 60);
  static const Duration _streamingFlushInterval = Duration(milliseconds: 500);

  final Isar isar;

  final List<ChatSession> _chatList = <ChatSession>[];
  final List<AIProviderConfig> _providers = <AIProviderConfig>[];
  List<Message> _currentMessages = <Message>[];

  final Map<int, GenerationAbortController> _abortControllers =
      <int, GenerationAbortController>{};
  final Map<int, _PendingContinuation> _pendingContinuations =
      <int, _PendingContinuation>{};
  final Set<int> _streamingMessageIds = <int>{};
  final Set<int> _dirtyStreamingMessageIds = <int>{};
  final Map<int, List<ToolExecutionLog>> _toolLogsByMessageId =
      <int, List<ToolExecutionLog>>{};

  Timer? _streamingNotifyTimer;
  Timer? _streamingFlushTimer;
  bool _isFlushingStreamingMessages = false;
  bool _scheduleFlushAgain = false;

  int? _currentMessagesChatId;
  int _loadedMessageCount = 0;
  bool _hasMoreHistory = false;
  bool _isLoadingMoreHistory = false;
  bool _initialized = false;

  List<ChatSession> get chatList => List.unmodifiable(_chatList);
  List<AIProviderConfig> get providers => List.unmodifiable(_providers);
  List<Message> get currentMessages => _currentMessages;
  bool get hasMoreHistory => _hasMoreHistory;
  bool get isLoadingMoreHistory => _isLoadingMoreHistory;
  Set<int> get streamingMessageIds => Set.unmodifiable(_streamingMessageIds);
  List<ToolExecutionLog> toolLogsForMessage(int messageId) {
    final logs = _toolLogsByMessageId[messageId];
    if (logs == null) return const <ToolExecutionLog>[];
    return List<ToolExecutionLog>.unmodifiable(logs);
  }

  ChatProvider(this.isar) {
    _loadFromLocal();
  }

  @override
  void dispose() {
    _streamingNotifyTimer?.cancel();
    _streamingFlushTimer?.cancel();
    super.dispose();
  }

  /// 统一封装状态变更通知，便于在 `part` 文件中安全调用。
  void _notifyStateChanged() {
    notifyListeners();
  }

  /// 判断一条消息当前是否处于流式生成状态。
  bool _isMessageStreaming(int messageId) {
    return _streamingMessageIds.contains(messageId);
  }

  /// 供 UI 查询指定消息是否正在流式输出。
  bool isMessageStreaming(int messageId) {
    return _isMessageStreaming(messageId);
  }

  /// 追加一条消息对应的工具调用日志。
  void _appendToolLogForMessage(int messageId, ToolExecutionLog log) {
    final logs =
        _toolLogsByMessageId.putIfAbsent(messageId, () => <ToolExecutionLog>[]);
    logs.add(log);
    _notifyStateChanged();
  }

  /// 覆盖设置消息的工具调用日志列表。
  void _setToolLogsForMessage(int messageId, List<ToolExecutionLog> logs) {
    if (logs.isEmpty) {
      _toolLogsByMessageId.remove(messageId);
    } else {
      _toolLogsByMessageId[messageId] = List<ToolExecutionLog>.from(logs);
    }
    _notifyStateChanged();
  }

  /// 删除消息关联的工具调用日志。
  void _removeToolLogsForMessage(int messageId) {
    _toolLogsByMessageId.remove(messageId);
  }

  /// 根据会话 ID 获取会话对象。
  ChatSession? getChatById(int id) {
    try {
      return _chatList.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 根据提供方 ID 获取提供方配置。
  AIProviderConfig? getProviderById(String id) {
    try {
      return _providers.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 创建新会话并写入本地数据库。
  Future<ChatSession> createNewChat({String? title}) async {
    final chat = ChatSession(
      title: title ?? '新会话 ${_chatList.length + 1}',
      createdAt: DateTime.now(),
      lastUpdated: DateTime.now(),
    );
    await isar.writeTxn(() async {
      await isar.chatSessions.put(chat);
    });

    _chatList.insert(0, chat);
    notifyListeners();
    return chat;
  }

  /// 删除会话及其全部消息。
  Future<void> deleteChat(int id) async {
    await isar.writeTxn(() async {
      await isar.chatSessions.delete(id);
      final count = await isar.messages.filter().chatIdEqualTo(id).deleteAll();
      AppLogger.i('删除会话(id: $id) 与 $count 条消息');
    });
    _chatList.removeWhere((c) => c.id == id);
    _abortControllers.remove(id);
    _pendingContinuations.remove(id);
    for (final message in _currentMessages.where((m) => m.chatId == id)) {
      _removeToolLogsForMessage(message.isarId);
    }
    _currentMessages.clear();
    notifyListeners();
  }

  /// 重命名会话标题。
  Future<void> renameChat(int id, String newTitle) async {
    final chat = getChatById(id);
    if (chat == null) return;

    chat.title = newTitle;
    await isar.writeTxn(() async {
      await isar.chatSessions.put(chat);
    });
    notifyListeners();
  }

  /// 更新会话参数并持久化。
  Future<void> updateChat(
    ChatSession chat, {
    String? providerId,
    String? model,
    String? systemPrompt,
    double? temperature,
    double? topP,
    int? maxTokens,
    int? maxConversationTurns,
    bool? toolCallingEnabled,
    int? maxToolCalls,
    bool? isStreaming,
    bool? isGenerating,
    DateTime? lastUpdated,
  }) async {
    chat.updateConfig(
      providerId: providerId,
      model: model,
      systemPrompt: systemPrompt,
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
      maxConversationTurns: maxConversationTurns,
      toolCallingEnabled: toolCallingEnabled,
      maxToolCalls: maxToolCalls,
      isStreaming: isStreaming,
      isGenerating: isGenerating,
      lastUpdated: lastUpdated,
    );

    await isar.writeTxn(() async {
      await isar.chatSessions.put(chat);
    });

    Logger().i('更新Chat ${chat.title}');
    notifyListeners();
  }

  /// 判断消息是否已产出可展示内容（正文或推理内容）。
  bool _hasMessageOutput(Message message) {
    return message.content.trim().isNotEmpty ||
        ((message.reasoning ?? '').trim().isNotEmpty);
  }

  /// 从本地数据库恢复会话与提供方状态。
  Future<void> _loadFromLocal() async {
    if (_initialized) return;
    _initialized = true;
    _abortControllers.clear();
    _pendingContinuations.clear();
    _streamingMessageIds.clear();
    _dirtyStreamingMessageIds.clear();
    _toolLogsByMessageId.clear();
    _currentMessagesChatId = null;
    _loadedMessageCount = 0;
    _hasMoreHistory = false;
    _isLoadingMoreHistory = false;

    final chats =
        await isar.chatSessions.where().sortByLastUpdatedDesc().findAll();
    await isar.writeTxn(() async {
      for (final chat in chats) {
        if (!chat.isGenerating) continue;
        chat.isGenerating = false;
        await isar.chatSessions.put(chat);
      }
    });
    _chatList
      ..clear()
      ..addAll(chats);

    final loadedProviders = await Storage.loadProviders();
    _providers
      ..clear()
      ..addAll(loadedProviders);

    notifyListeners();
  }
}
