import 'dart:async';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:logger/web.dart';
import 'package:now_chat/core/models/ai_provider_config.dart';
import 'package:now_chat/core/network/api_service.dart';
import 'package:now_chat/util/app_logger.dart';

import '../core/models/chat_session.dart';
import '../core/models/message.dart';
import '../util/storage.dart';

class _PendingContinuation {
  final int assistantMessageId;
  final int anchorUserMessageId;

  const _PendingContinuation({
    required this.assistantMessageId,
    required this.anchorUserMessageId,
  });
}

class ChatProvider with ChangeNotifier {
  final Isar isar;

  final List<ChatSession> _chatList = [];
  final List<AIProviderConfig> _providers = [];
  List<Message> _currentMessages = [];
  final Map<int, GenerationAbortController> _abortControllers =
      <int, GenerationAbortController>{};
  final Map<int, _PendingContinuation> _pendingContinuations =
      <int, _PendingContinuation>{};

  bool _initialized = false;

  List<ChatSession> get chatList => List.unmodifiable(_chatList);
  List<AIProviderConfig> get providers => List.unmodifiable(_providers);
  List<Message> get currentMessages => _currentMessages;

  ChatProvider(this.isar) {
    _loadFromLocal();
  }

  Future<Message?> getLastMessage(int id) async {
    final messages = await getMessagesByChatId(id);
    return messages.isEmpty ? null : messages.last;
  }

  // 获取会话
  ChatSession? getChatById(int id) {
    try {
      return _chatList.firstWhere((c) => c.id == id);
    } catch (e) {
      return null;
    }
  }

  // 获取Provider
  AIProviderConfig? getProviderById(String id) {
    try {
      return _providers.firstWhere((p) => p.id == id);
    } catch (e) {
      return null;
    }
  }

  /// 加载某个会话的所有消息
  Future<void> loadMessages(int? chatId) async {
    if (chatId == null) {
      _currentMessages.clear();
      return;
    }
    final msgs = await getMessagesByChatId(chatId);
    _currentMessages = msgs;
    AppLogger.i("加载会话(id: $chatId) ${msgs.length} 消息");
    notifyListeners();
  }

  // 创建新会话
  Future<ChatSession> createNewChat({String? title}) async {
    final chat = ChatSession(
      title: title ?? "新会话 ${_chatList.length + 1}",
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

  // 删除会话
  Future<void> deleteChat(int id) async {
    await isar.writeTxn(() async {
      await isar.chatSessions.delete(id);
      // 删除对应消息
      final count = await isar.messages.filter().chatIdEqualTo(id).deleteAll();
      AppLogger.i("删除会话(id: $id) 与 $count 条消息");
    });
    _chatList.removeWhere((c) => c.id == id);
    _abortControllers.remove(id);
    _pendingContinuations.remove(id);
    _currentMessages.clear();
    notifyListeners();
  }

  // 重命名会话
  Future<void> renameChat(int id, String newTitle) async {
    final chat = getChatById(id);
    if (chat == null) return;

    chat.title = newTitle;
    await isar.writeTxn(() async {
      await isar.chatSessions.put(chat);
    });
    notifyListeners();
  }

  // 更新会话信息
  Future<void> updateChat(
    ChatSession chat, {
    String? providerId,
    String? model,
    String? systemPrompt,
    double? temperature,
    double? topP,
    int? maxTokens,
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
      isStreaming: isStreaming,
      isGenerating: isGenerating,
      lastUpdated: lastUpdated,
    );

    await isar.writeTxn(() async {
      await isar.chatSessions.put(chat);
    });

    Logger().i("更新Chat ${chat.title}");
    notifyListeners();
  }

  // 获取会话消息
  Future<List<Message>> getMessagesByChatId(int chatId) async {
    return await isar.messages
        .filter()
        .chatIdEqualTo(chatId)
        .sortByTimestamp()
        .findAll();
  }

  // 添加消息
  Future<void> saveMessage(Message message) async {
    // 更新 _currentMessages
    final index = _currentMessages.indexWhere(
      (m) => m.isarId == message.isarId,
    );
    if (index >= 0) {
      // 已存在 -> 替换
      _currentMessages[index] = message;
    } else {
      // 不存在 -> 添加
      _currentMessages.add(message);
    }
    await isar.writeTxn(() async {
      await isar.messages.put(message);
    });
    notifyListeners();
  }

  // 删除消息
  Future<void> deleteMessage(int isarId) async {
    await isar.writeTxn(() async {
      await isar.messages.delete(isarId);
    });

    AppLogger.i("删除消息: $isarId");
    // 从内存中同步删除
    final removedIndex = _currentMessages.indexWhere((m) => m.isarId == isarId);
    final removedChatId =
        removedIndex >= 0 ? _currentMessages[removedIndex].chatId : null;
    _currentMessages.removeWhere((m) => m.isarId == isarId);
    if (removedChatId != null) {
      final pending = _pendingContinuations[removedChatId];
      if (pending != null && pending.assistantMessageId == isarId) {
        _pendingContinuations.remove(removedChatId);
      }
    }
    notifyListeners();
  }

  // 刷新API的模型列表
  Future<void> refreshConfigModels(
    String id,
    List<String> models, {
    Map<String, String>? modelRemarks,
    Map<String, ModelFeatureOptions>? modelCapabilities,
  }) async {
    final provider = getProviderById(id);
    if (provider == null) return;
    provider.updateConfig(
      models: models,
      modelRemarks: modelRemarks ?? provider.modelRemarks,
      modelCapabilities: modelCapabilities ?? provider.modelCapabilities,
    );
    await _saveProvidersl();
    notifyListeners();
  }

  // 创建Provider
  Future<void> createNewProvider(AIProviderConfig provider) async {
    _providers.insert(0, provider);
    await _saveProvidersl();
    notifyListeners();
  }

  // 删除Provider
  Future<void> deleteProvider(String id) async {
    _providers.removeWhere((p) => p.id == id);
    await _saveProvidersl();
    notifyListeners();
  }

  //更新Provider信息
  Future<void> updateProvider(
    String providerId, {
    String? name,
    ProviderType? type,
    RequestMode? requestMode,
    String? baseUrl,
    String? urlPath,
    String? apiKey,
    List<String>? models,
    Map<String, String>? modelRemarks,
    Map<String, ModelFeatureOptions>? modelCapabilities,
  }) async {
    AIProviderConfig? provider = getProviderById(providerId);
    if (provider == null) return;
    provider.updateConfig(
      name: name,
      type: type,
      requestMode: requestMode,
      baseUrl: baseUrl,
      apiKey: apiKey,
      urlPath: urlPath,
      models: models,
      modelRemarks: modelRemarks,
      modelCapabilities: modelCapabilities,
    );
    await _saveProvidersl();
    notifyListeners();
  }

  // 获取api模型列表
  Future<List<String>> fetchModels(
    AIProviderConfig provider,
    String baseUrl,
    String apiKey,
  ) async {
    final models = await ApiService.fetchModels(provider, baseUrl, apiKey);
    return models;
  }

  bool canContinueAssistantMessage(int chatId, int assistantMessageId) {
    final pending = _pendingContinuations[chatId];
    if (pending == null) return false;
    return pending.assistantMessageId == assistantMessageId;
  }

  void interruptGeneration(int chatId) {
    final controller = _abortControllers[chatId];
    if (controller == null) return;
    controller.abort();
    AppLogger.i("已请求中断会话($chatId)的生成");
  }

  Future<void> continueGeneratingAssistantMessage(
    int chatId,
    bool isStreaming,
  ) async {
    final chat = getChatById(chatId);
    if (chat == null || chat.isGenerating) return;
    final provider = getProviderById(chat.providerId ?? '');
    if (provider == null) return;
    final pending = _pendingContinuations[chatId];
    if (pending == null) return;

    final messages = await getMessagesByChatId(chatId);
    final assistantIndex = messages.indexWhere(
      (m) => m.isarId == pending.assistantMessageId,
    );
    if (assistantIndex == -1) {
      _pendingContinuations.remove(chatId);
      notifyListeners();
      return;
    }
    final assistantMessage = messages[assistantIndex];
    final anchorIndex = messages.lastIndexWhere(
      (m) => m.isarId == pending.anchorUserMessageId,
    );
    if (anchorIndex == -1 || anchorIndex >= assistantIndex) {
      _pendingContinuations.remove(chatId);
      notifyListeners();
      return;
    }

    final requestMessages = <Message>[
      ...messages.take(assistantIndex + 1),
      Message(
        chatId: chatId,
        role: 'user',
        content: '继续上一条回复未完成的内容，从中断位置接着写，不要重复已输出内容。',
        timestamp: DateTime.now(),
      ),
    ];

    final abortController = GenerationAbortController();
    _abortControllers[chatId] = abortController;
    await _setChatGenerating(chat, true);
    bool responseStarted = false;
    bool interrupted = false;

    try {
      final effectiveStreaming =
          isStreaming && provider.requestMode.supportsStreaming;
      if (isStreaming && !provider.requestMode.supportsStreaming) {
        AppLogger.w("当前请求方式不支持流式输出，已自动回退为普通请求");
      }

      if (effectiveStreaming) {
        await ApiService.sendChatRequestStreaming(
          provider: provider,
          session: chat,
          isar: isar,
          abortController: abortController,
          overrideMessages: requestMessages,
          onStream: (deltaContent, deltaReasoning) async {
            bool notifyNeeded = false;
            if (deltaReasoning != null && deltaReasoning.isNotEmpty) {
              assistantMessage.reasoning =
                  (assistantMessage.reasoning ?? '') + deltaReasoning;
              notifyNeeded = true;
            }
            if (deltaContent.isNotEmpty) {
              responseStarted = true;
              assistantMessage.content += deltaContent;
              notifyNeeded = true;
            }
            if (notifyNeeded) {
              await saveMessage(assistantMessage);
            }
          },
          onDone: () async {
            await saveMessage(assistantMessage);
          },
        );
      } else {
        final response = await ApiService.sendChatRequest(
          provider: provider,
          session: chat,
          isar: isar,
          abortController: abortController,
          overrideMessages: requestMessages,
        );
        final content = (response['content'] ?? '').toString();
        final reasoning = response['reasoning']?.toString();
        assistantMessage
          ..content += content
          ..reasoning =
              ((assistantMessage.reasoning ?? '') + (reasoning ?? '')).trim()
          ..reasoningTimeMs = response['reasoningTimeMs'];
        if (content.trim().isNotEmpty) {
          responseStarted = true;
        }
        await saveMessage(assistantMessage);
      }
    } on GenerationAbortedException {
      interrupted = true;
      AppLogger.i("继续生成已中断(chatId=$chatId)");
    } catch (e) {
      AppLogger.w("继续生成失败(chatId=$chatId): $e");
    } finally {
      _abortControllers.remove(chatId);
      await _setChatGenerating(chat, false);
    }

    final hasAnyOutput = assistantMessage.content.trim().isNotEmpty;
    if (interrupted && hasAnyOutput) {
      // 用户手动中断时，无论本次是否已开始新增输出，都保留“继续”入口。
      _pendingContinuations[chatId] = pending;
    } else if (responseStarted) {
      _pendingContinuations.remove(chatId);
    }
    notifyListeners();
  }

  // 重新生成消息
  Future<void> regenerateMessage(int chatId, bool isStreaming) async {
    final chat = getChatById(chatId);
    if (chat == null || chat.isGenerating) return;
    final provider = getProviderById(chat.providerId ?? '');
    if (provider == null) return;

    final messages = await getMessagesByChatId(chatId);
    if (messages.isEmpty) return;

    final lastUserIndex = messages.lastIndexWhere((m) => m.role == 'user');
    if (lastUserIndex == -1) return;

    final trailingAssistantMessages =
        messages
            .skip(lastUserIndex + 1)
            .where((m) => m.role == 'assistant')
            .toList();

    final backupAssistantMessages = List<Message>.from(
      trailingAssistantMessages,
    );
    await _deleteMessagesByIds(
      trailingAssistantMessages.map((m) => m.isarId).toSet(),
    );

    final abortController = GenerationAbortController();
    _abortControllers[chatId] = abortController;
    await _setChatGenerating(chat, true);
    bool interrupted = false;
    try {
      final aiMsg = Message(
        chatId: chatId,
        role: 'assistant',
        content: '',
        reasoning: '',
        timestamp: DateTime.now(),
      );
      await saveMessage(aiMsg);

      final effectiveStreaming =
          isStreaming && provider.requestMode.supportsStreaming;
      if (isStreaming && !provider.requestMode.supportsStreaming) {
        AppLogger.w("当前请求方式不支持流式输出，已自动回退为普通请求");
      }

      String? failureReason;
      bool responseStarted = false;

      if (effectiveStreaming) {
        Timer? reasoningTimer;
        DateTime? reasoningStartTime;
        try {
          await ApiService.sendChatRequestStreaming(
            provider: provider,
            session: chat,
            isar: isar,
            abortController: abortController,
            onStream: (deltaContent, deltaReasoning) async {
              bool notifyNeeded = false;

              if (deltaReasoning != null && deltaReasoning.isNotEmpty) {
                if (reasoningStartTime == null) {
                  reasoningStartTime = DateTime.now();
                  reasoningTimer = Timer.periodic(
                    const Duration(milliseconds: 100),
                    (_) async {
                      aiMsg.reasoningTimeMs =
                          DateTime.now()
                              .difference(reasoningStartTime!)
                              .inMilliseconds;
                      notifyListeners();
                    },
                  );
                }
                aiMsg.reasoning = (aiMsg.reasoning ?? '') + deltaReasoning;
                notifyNeeded = true;
              }

              if (deltaContent.isNotEmpty) {
                responseStarted = true;
                reasoningTimer?.cancel();
                aiMsg.content += deltaContent;
                notifyNeeded = true;
              }

              if (notifyNeeded) await saveMessage(aiMsg);
            },
            onDone: () async {
              reasoningTimer?.cancel();
              if (reasoningStartTime != null) {
                aiMsg.reasoningTimeMs =
                    DateTime.now()
                        .difference(reasoningStartTime!)
                        .inMilliseconds;
              }
              await saveMessage(aiMsg);
            },
          );
        } on GenerationAbortedException {
          interrupted = true;
        } catch (e) {
          failureReason = e.toString();
        }
      } else {
        try {
          final response = await ApiService.sendChatRequest(
            provider: provider,
            session: chat,
            isar: isar,
            abortController: abortController,
          );
          aiMsg
            ..content = response['content'] ?? ''
            ..reasoning = response['reasoning']
            ..reasoningTimeMs = response['reasoningTimeMs'];
          if (aiMsg.content.trim().isNotEmpty) {
            responseStarted = true;
          }
          await saveMessage(aiMsg);
        } on GenerationAbortedException {
          interrupted = true;
        } catch (e) {
          failureReason = e.toString();
        }
      }

      final hasAnyOutput =
          aiMsg.content.trim().isNotEmpty ||
          ((aiMsg.reasoning ?? '').trim().isNotEmpty);
      final shouldRestoreOldReply = !responseStarted && !interrupted;
      final shouldKeepInterruptedPartial = interrupted && hasAnyOutput;
      if (shouldRestoreOldReply) {
        await _deleteMessagesByIds({aiMsg.isarId});
        if (backupAssistantMessages.isNotEmpty) {
          await _restoreMessages(backupAssistantMessages);
        }
        if (failureReason != null) {
          AppLogger.w("重新发送失败，已恢复旧回复: $failureReason");
        } else {
          AppLogger.w("重新发送未产出有效内容，已恢复旧回复");
        }
      } else if (shouldKeepInterruptedPartial) {
        _pendingContinuations[chatId] = _PendingContinuation(
          assistantMessageId: aiMsg.isarId,
          anchorUserMessageId: messages[lastUserIndex].isarId,
        );
      } else if (interrupted && !hasAnyOutput) {
        await _deleteMessagesByIds({aiMsg.isarId});
        if (backupAssistantMessages.isNotEmpty) {
          await _restoreMessages(backupAssistantMessages);
        }
        _pendingContinuations.remove(chatId);
      } else {
        _pendingContinuations.remove(chatId);
      }
    } finally {
      _abortControllers.remove(chatId);
      await _setChatGenerating(chat, false);
    }
  }

  // 发送消息
  Future<void> sendMessage(
    int chatId,
    String userContent,
    bool isStreaming,
    List<String>? attachmentPaths,
  ) async {
    AppLogger.i("发送消息");
    final chat = getChatById(chatId);
    if (chat == null) return;
    final provider = getProviderById(chat.providerId ?? '');
    if (provider == null) {
      await saveMessage(
        Message(
          chatId: chatId,
          role: 'assistant',
          content: '无效的 Provider',
          timestamp: DateTime.now(),
        ),
      );
      notifyListeners();
      return;
    }
    _pendingContinuations.remove(chatId);
    final abortController = GenerationAbortController();
    _abortControllers[chatId] = abortController;
    await _setChatGenerating(chat, true);
    bool interrupted = false;
    try {
      // 添加用户消息
      final userMsg = Message(
        chatId: chatId,
        role: 'user',
        content: userContent,
        imagePaths: attachmentPaths,
        timestamp: DateTime.now(),
      );

      await saveMessage(userMsg);
      notifyListeners();

      // 临时 assistant 消息
      final aiMsg = Message(
        chatId: chatId,
        role: 'assistant',
        content: '',
        reasoning: '',
        timestamp: DateTime.now(),
      );

      await saveMessage(aiMsg);
      notifyListeners();

      // 流式对话
      final effectiveStreaming =
          isStreaming && provider.requestMode.supportsStreaming;
      bool responseStarted = false;
      if (isStreaming && !provider.requestMode.supportsStreaming) {
        AppLogger.w("当前请求方式不支持流式输出，已自动回退为普通请求");
      }

      if (effectiveStreaming) {
        Timer? reasoningTimer;
        DateTime? reasoningStartTime;

        try {
          await ApiService.sendChatRequestStreaming(
            provider: provider,
            session: chat,
            isar: isar,
            abortController: abortController,
            onStream: (deltaContent, deltaReasoning) async {
              bool notifyNeeded = false;

              if (deltaReasoning != null && deltaReasoning.isNotEmpty) {
                if (reasoningStartTime == null) {
                  reasoningStartTime = DateTime.now();
                  reasoningTimer = Timer.periodic(
                    const Duration(milliseconds: 100),
                    (_) async {
                      aiMsg.reasoningTimeMs =
                          DateTime.now()
                              .difference(reasoningStartTime!)
                              .inMilliseconds;
                      notifyListeners();
                    },
                  );
                }
                aiMsg.reasoning = (aiMsg.reasoning ?? '') + deltaReasoning;
                notifyNeeded = true;
              }

              if (deltaContent.isNotEmpty) {
                responseStarted = true;
                reasoningTimer?.cancel();
                aiMsg.content += deltaContent;
                notifyNeeded = true;
              }

              if (notifyNeeded) await saveMessage(aiMsg);
            },
            onDone: () async {
              AppLogger.i("onDone: 流式请求结束");
              reasoningTimer?.cancel();
              if (reasoningStartTime != null) {
                aiMsg.reasoningTimeMs =
                    DateTime.now()
                        .difference(reasoningStartTime!)
                        .inMilliseconds;
              }
              await saveMessage(aiMsg);
            },
          );
        } on GenerationAbortedException {
          interrupted = true;
        } catch (e) {
          aiMsg.content = "AI 响应出错：${e.toString()}";
          await saveMessage(aiMsg);
        }
      } else {
        try {
          final response = await ApiService.sendChatRequest(
            provider: provider,
            session: chat,
            isar: isar,
            abortController: abortController,
          );
          aiMsg
            ..content = response['content'] ?? ''
            ..reasoning = response['reasoning']
            ..reasoningTimeMs = response['reasoningTimeMs'];
          if (aiMsg.content.trim().isNotEmpty) {
            responseStarted = true;
          }
          await saveMessage(aiMsg);
        } on GenerationAbortedException {
          interrupted = true;
        } catch (e) {
          aiMsg.content = '请求失败: $e';
          await saveMessage(aiMsg);
        }
      }

      final hasAnyOutput =
          aiMsg.content.trim().isNotEmpty ||
          ((aiMsg.reasoning ?? '').trim().isNotEmpty);
      if (interrupted && hasAnyOutput) {
        _pendingContinuations[chatId] = _PendingContinuation(
          assistantMessageId: aiMsg.isarId,
          anchorUserMessageId: userMsg.isarId,
        );
      } else if (interrupted && !hasAnyOutput) {
        await _deleteMessagesByIds({aiMsg.isarId});
      } else if (responseStarted) {
        _pendingContinuations.remove(chatId);
      }
    } finally {
      _abortControllers.remove(chatId);
      await _setChatGenerating(chat, false);
    }
    notifyListeners();
  }

  Future<void> _setChatGenerating(ChatSession chat, bool isGenerating) async {
    chat.isGenerating = isGenerating;
    await isar.writeTxn(() async {
      await isar.chatSessions.put(chat);
    });
    notifyListeners();
  }

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
    for (final chatId in removedChatIds) {
      final pending = _pendingContinuations[chatId];
      if (pending != null && ids.contains(pending.assistantMessageId)) {
        _pendingContinuations.remove(chatId);
      }
    }
    notifyListeners();
  }

  Future<void> _restoreMessages(List<Message> messages) async {
    if (messages.isEmpty) return;
    await isar.writeTxn(() async {
      for (final msg in messages) {
        await isar.messages.put(msg);
      }
    });
    _currentMessages.addAll(messages);
    _currentMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    notifyListeners();
  }

  // 本地存取
  Future<void> _loadFromLocal() async {
    if (_initialized) return;
    _initialized = true;
    _abortControllers.clear();
    _pendingContinuations.clear();

    final chats =
        await isar.chatSessions.where().sortByLastUpdatedDesc().findAll();
    await isar.writeTxn(() async {
      for (var chat in chats) {
        if (chat.isGenerating) {
          chat.isGenerating = false;
          await isar.chatSessions.put(chat);
        }
      }
    });
    _chatList.clear();
    _chatList.addAll(chats);

    final loadedProviders = await Storage.loadProviders();
    _providers.clear();
    _providers.addAll(loadedProviders);

    notifyListeners();
  }

  // 保存Provider到本地
  Future<void> _saveProvidersl() async {
    await Storage.saveProviders(_providers);
  }
}
