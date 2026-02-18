part of '../chat_provider.dart';

extension ChatProviderMessageStore on ChatProvider {
  /// 将消息写入当前会话内存列表（存在则更新，不存在则追加）。
  bool _upsertMessageInMemory(Message message) {
    final index = _currentMessages.indexWhere((m) => m.isarId == message.isarId);
    if (index >= 0) {
      _currentMessages[index] = message;
    } else {
      _currentMessages.add(message);
    }
    if (_currentMessagesChatId == message.chatId) {
      _loadedMessageCount = _currentMessages.length;
    }
    return true;
  }

  /// 清理单条消息相关的流式状态。
  void _removeMessageStateById(int messageId) {
    _streamingMessageIds.remove(messageId);
    _dirtyStreamingMessageIds.remove(messageId);
  }

  /// 降低流式增量刷新频率，减少高频 notifyListeners 带来的卡顿。
  void _scheduleStreamingNotify() {
    if (_streamingNotifyTimer != null) return;
    _streamingNotifyTimer = Timer(ChatProvider._streamingUiThrottle, () {
      _streamingNotifyTimer = null;
      _notifyStateChanged();
    });
  }

  /// 按固定间隔将流式脏数据批量刷入 Isar。
  void _scheduleStreamingFlush() {
    if (_streamingFlushTimer != null) return;
    _streamingFlushTimer = Timer(ChatProvider._streamingFlushInterval, () async {
      _streamingFlushTimer = null;
      await _flushDirtyStreamingMessages();
      if (_dirtyStreamingMessageIds.isNotEmpty) {
        _scheduleStreamingFlush();
      }
    });
  }

  /// 批量持久化处于流式更新中的消息。
  Future<void> _flushDirtyStreamingMessages() async {
    if (_isFlushingStreamingMessages) {
      _scheduleFlushAgain = true;
      return;
    }
    if (_dirtyStreamingMessageIds.isEmpty) return;

    _isFlushingStreamingMessages = true;
    try {
      do {
        _scheduleFlushAgain = false;
        final ids = Set<int>.from(_dirtyStreamingMessageIds);
        final toPersist =
            _currentMessages.where((m) => ids.contains(m.isarId)).toList();
        if (toPersist.isEmpty) {
          // 当前内存列表里找不到对应消息时，保留 dirty 标记等待后续重试。
          return;
        }
        await isar.writeTxn(() async {
          for (final msg in toPersist) {
            await isar.messages.put(msg);
          }
        });
        _dirtyStreamingMessageIds.removeAll(ids);
      } while (_scheduleFlushAgain || _dirtyStreamingMessageIds.isNotEmpty);
    } finally {
      _isFlushingStreamingMessages = false;
    }
  }

  /// 标记消息进入流式生成状态。
  void beginStreamingMessage(Message message) {
    _streamingMessageIds.add(message.isarId);
    _upsertMessageInMemory(message);
    _notifyStateChanged();
  }

  /// 应用流式增量并进入节流刷新队列。
  void updateStreamingMessage(Message message) {
    _upsertMessageInMemory(message);
    _dirtyStreamingMessageIds.add(message.isarId);
    _scheduleStreamingNotify();
    _scheduleStreamingFlush();
  }

  /// 结束流式状态并确保最终落库。
  Future<void> endStreamingMessage(Message message) async {
    _upsertMessageInMemory(message);
    _dirtyStreamingMessageIds.add(message.isarId);
    await _flushDirtyStreamingMessages();
    _removeMessageStateById(message.isarId);
    _notifyStateChanged();
  }

  /// 保存消息到内存与数据库。
  Future<void> saveMessage(Message message) async {
    _upsertMessageInMemory(message);
    await isar.writeTxn(() async {
      await isar.messages.put(message);
    });
    _notifyStateChanged();
  }

  /// 删除单条消息并同步清理内存/状态。
  Future<void> deleteMessage(int isarId) async {
    await isar.writeTxn(() async {
      await isar.messages.delete(isarId);
    });

    AppLogger.i('删除消息: $isarId');
    final removedIndex = _currentMessages.indexWhere((m) => m.isarId == isarId);
    final removedChatId =
        removedIndex >= 0 ? _currentMessages[removedIndex].chatId : null;
    _currentMessages.removeWhere((m) => m.isarId == isarId);
    _removeMessageStateById(isarId);
    if (_currentMessagesChatId != null && removedChatId == _currentMessagesChatId) {
      _loadedMessageCount = _currentMessages.length;
    }
    if (removedChatId != null) {
      final pending = _pendingContinuations[removedChatId];
      if (pending != null && pending.assistantMessageId == isarId) {
        _pendingContinuations.remove(removedChatId);
      }
    }
    _notifyStateChanged();
  }

  /// 按 ID 批量删除消息。
  Future<void> _deleteMessagesByIds(Set<int> ids) async {
    if (ids.isEmpty) return;
    final removedChatIds =
        _currentMessages
            .where((m) => ids.contains(m.isarId))
            .map((m) => m.chatId)
            .toSet();
    await isar.writeTxn(() async {
      for (final id in ids) {
        await isar.messages.delete(id);
      }
    });
    _currentMessages.removeWhere((m) => ids.contains(m.isarId));
    for (final id in ids) {
      _removeMessageStateById(id);
    }
    if (_currentMessagesChatId != null) {
      _loadedMessageCount = _currentMessages.length;
    }
    for (final chatId in removedChatIds) {
      final pending = _pendingContinuations[chatId];
      if (pending != null && ids.contains(pending.assistantMessageId)) {
        _pendingContinuations.remove(chatId);
      }
    }
    _notifyStateChanged();
  }

  /// 批量恢复消息（用于重新生成失败回滚）。
  Future<void> _restoreMessages(List<Message> messages) async {
    if (messages.isEmpty) return;
    await isar.writeTxn(() async {
      for (final msg in messages) {
        await isar.messages.put(msg);
      }
    });
    _currentMessages.addAll(messages);
    _currentMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (_currentMessagesChatId != null) {
      _loadedMessageCount = _currentMessages.length;
    }
    _notifyStateChanged();
  }
}
