part of '../chat_provider.dart';

/// ChatProviderMessageStore 扩展方法集合。
extension ChatProviderMessageStore on ChatProvider {
  /// 将消息写入当前会话内存列表（存在则更新，不存在则追加）。
  ///
  /// 返回值表示该消息是否属于“当前正在展示的会话”并已写入内存列表。
  /// 非当前会话消息不会进入 `_currentMessages`，避免串会话污染 UI。
  bool _upsertMessageInMemory(Message message) {
    // 仅允许“已绑定的当前会话”写入内存列表。
    // 当 `_currentMessagesChatId == null`（例如新建会话尚未绑定）时，拒绝所有写入，
    // 防止后台会话的流式消息误入当前页面。
    if (_currentMessagesChatId == null || _currentMessagesChatId != message.chatId) {
      return false;
    }
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

  /// 非当前会话流式消息直接写库，避免污染当前页面内存列表。
  Future<void> _persistOffscreenStreamingMessage(Message message) async {
    await isar.writeTxn(() async {
      await isar.messages.put(message);
    });
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
  ///
  /// 该方法会串行执行，避免并发事务导致落库顺序混乱。
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
    final insertedInCurrent = _upsertMessageInMemory(message);
    if (insertedInCurrent) {
      _notifyStateChanged();
      return;
    }
    // 后台会话不触发当前页面重建，只确保内容持续落库。
    unawaited(_persistOffscreenStreamingMessage(message));
  }

  /// 应用流式增量并进入节流刷新队列。
  void updateStreamingMessage(Message message) {
    final insertedInCurrent = _upsertMessageInMemory(message);
    if (!insertedInCurrent) {
      // 非当前会话：直接落库，不参与当前会话节流刷新队列。
      unawaited(_persistOffscreenStreamingMessage(message));
      return;
    }
    _dirtyStreamingMessageIds.add(message.isarId);
    _scheduleStreamingNotify();
    _scheduleStreamingFlush();
  }

  /// 结束流式状态并确保最终落库。
  Future<void> endStreamingMessage(Message message) async {
    final insertedInCurrent = _upsertMessageInMemory(message);
    if (insertedInCurrent) {
      _dirtyStreamingMessageIds.add(message.isarId);
      await _flushDirtyStreamingMessages();
    } else {
      await _persistOffscreenStreamingMessage(message);
    }
    _removeMessageStateById(message.isarId);
    if (insertedInCurrent) {
      _notifyStateChanged();
    }
  }

  /// 保存消息到内存与数据库。
  ///
  /// 普通消息直接同步落库；流式消息应优先走 updateStreamingMessage。
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
    _removeToolLogsForMessage(isarId);
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
      _removeToolLogsForMessage(id);
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
    // 仅将“当前会话”的恢复消息回写到内存列表，避免串会话显示。
    final visibleMessages =
        _currentMessagesChatId == null
            ? const <Message>[]
            : messages.where((m) => m.chatId == _currentMessagesChatId).toList();
    if (visibleMessages.isEmpty) {
      return;
    }
    _currentMessages.addAll(visibleMessages);
    _currentMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (_currentMessagesChatId != null) {
      _loadedMessageCount = _currentMessages.length;
    }
    _notifyStateChanged();
  }
}
