part of '../chat_provider.dart';

/// ChatProviderHistory 扩展方法集合。
extension ChatProviderHistory on ChatProvider {
  /// 加载某个会话的消息列表（兼容旧调用入口）。
  Future<void> loadMessages(int? chatId) async {
    await loadInitialMessages(chatId);
  }

  /// 加载会话最新一页消息，默认只取最近 50 条以降低首屏渲染开销。
  Future<void> loadInitialMessages(
    int? chatId, {
    int limit = ChatProvider._defaultMessagePageSize,
  }) async {
    if (chatId == null) {
      _currentMessages.clear();
      _currentMessagesChatId = null;
      _loadedMessageCount = 0;
      _hasMoreHistory = false;
      _isLoadingMoreHistory = false;
      _notifyStateChanged();
      return;
    }
    final totalCount = await isar.messages.filter().chatIdEqualTo(chatId).count();
    final latestDesc =
        await isar.messages
            .filter()
            .chatIdEqualTo(chatId)
            .sortByTimestampDesc()
            .limit(limit)
            .findAll();
    final latest = latestDesc.reversed.toList();
    _currentMessages = latest;
    _currentMessagesChatId = chatId;
    _loadedMessageCount = latest.length;
    _hasMoreHistory = _loadedMessageCount < totalCount;
    _isLoadingMoreHistory = false;
    AppLogger.i('加载会话(id: $chatId) 首屏 ${latest.length}/$totalCount 条消息');
    _notifyStateChanged();
  }

  /// 继续向上加载更早历史消息。
  Future<void> loadMoreHistory({
    int limit = ChatProvider._defaultMessagePageSize,
  }) async {
    final chatId = _currentMessagesChatId;
    if (chatId == null) return;
    if (_isLoadingMoreHistory || !_hasMoreHistory) return;

    _isLoadingMoreHistory = true;
    _notifyStateChanged();
    try {
      final totalCount = await isar.messages.filter().chatIdEqualTo(chatId).count();
      final olderDesc =
          await isar.messages
              .filter()
              .chatIdEqualTo(chatId)
              .sortByTimestampDesc()
              .offset(_loadedMessageCount)
              .limit(limit)
              .findAll();
      final olderMessages = olderDesc.reversed.toList();
      if (olderMessages.isNotEmpty) {
        _currentMessages = <Message>[...olderMessages, ..._currentMessages];
        _loadedMessageCount = _currentMessages.length;
      }
      _hasMoreHistory = _loadedMessageCount < totalCount;
    } finally {
      _isLoadingMoreHistory = false;
      _notifyStateChanged();
    }
  }

  /// 获取指定会话的完整消息列表。
  Future<List<Message>> getMessagesByChatId(int chatId) async {
    return isar.messages.filter().chatIdEqualTo(chatId).sortByTimestamp().findAll();
  }

  /// 获取会话最后一条消息。
  Future<Message?> getLastMessage(int chatId) async {
    final messages = await getMessagesByChatId(chatId);
    return messages.isEmpty ? null : messages.last;
  }
}
