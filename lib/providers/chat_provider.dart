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

class ChatProvider with ChangeNotifier {
  final Isar isar;

  final List<ChatSession> _chatList = [];
  final List<AIProviderConfig> _providers = [];
  List<Message> _currentMessages = [];

  

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
      lastUpdated: DateTime.now()
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
    final index = _currentMessages.indexWhere((m) => m.isarId == message.isarId);
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
  _currentMessages.removeWhere((m) => m.isarId == isarId);
    notifyListeners();
  }

  // 刷新API的模型列表
  Future<void> refreshConfigModels(String id, List<String> models) async {
    final provider = getProviderById(id);
    if (provider == null) return;
    provider.models = models;
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
       String? baseUrl,
       String? urlPath,
       String? apiKey,
       List<String>? models,
    }) async {
      AIProviderConfig? provider = getProviderById(providerId);
      if(provider == null) return;
      provider.updateConfig(
        name: name,
        type: type,
        baseUrl: baseUrl,
        apiKey: apiKey,
        urlPath: urlPath,
        models: models
      );
      _saveProvidersl;
      notifyListeners();
    }

  // 获取api模型列表
  Future<List<String>> fetchModels(AIProviderConfig provider, String baseUrl, String apiKey) async {
    final models = await ApiService.fetchModels(provider, baseUrl, apiKey);
    return models;
  }

  // 重新生成消息
  Future<void> regenerateMessage(int chatId, bool isStreaming) async {
    // TODO
  }

  // 发送消息
  Future<void> sendMessage(int chatId, String userContent, bool isStreaming) async {
    AppLogger.i("发送消息");
    final chat = getChatById(chatId);
    if (chat == null) return;
    final provider = getProviderById(chat.providerId ?? '');
    if (provider == null) {
      await saveMessage(Message(
        chatId: chatId,
        role: 'assistant',
        content: '无效的 Provider',
        timestamp: DateTime.now(),
      ));
      notifyListeners();
      return;
    }
    updateChat(
      chat,
      isGenerating: true,
      lastUpdated: DateTime.now()
    );

    // 添加用户消息
    final userMsg = Message(
        chatId: chatId,
        role: 'user',
        content: userContent,
        timestamp: DateTime.now()
      );

    await saveMessage(userMsg);
    notifyListeners();

    // 临时 assistant 消息
    final aiMsg = Message(
      chatId: chatId,
      role: 'assistant',
      content: '',
      reasoning: '',
      timestamp: DateTime.now()
    );

    await saveMessage(aiMsg);
    notifyListeners();
    

    // 流式对话
    if (isStreaming) {
      Timer? reasoningTimer;
      DateTime? reasoningStartTime;

      try {
        await ApiService.sendChatRequestStreaming(
          provider: provider,
          session: chat,
          isar: isar,
          onStream: (deltaContent, deltaReasoning) async {
            bool notifyNeeded = false;

            if (deltaReasoning != null && deltaReasoning.isNotEmpty) {
              if (reasoningStartTime == null) {
                reasoningStartTime = DateTime.now();
                reasoningTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
                  aiMsg.reasoningTimeMs =
                      DateTime.now().difference(reasoningStartTime!).inMilliseconds;
                  notifyListeners();
                });
              }
              aiMsg.reasoning = (aiMsg.reasoning ?? '') + deltaReasoning;
              notifyNeeded = true;
            }

            if (deltaContent.isNotEmpty) {
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
                  DateTime.now().difference(reasoningStartTime!).inMilliseconds;
            }
            // 确保生成状态关闭
            final chat = getChatById(chatId);
            if (chat != null) {
              chat.isGenerating = false;
              await isar.writeTxn(() async {
                await isar.chatSessions.put(chat);
              });
              notifyListeners();
            }
            await saveMessage(aiMsg);
          },
        );
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
        );
        aiMsg
          ..content = response['content'] ?? ''
          ..reasoning = response['reasoning']
          ..reasoningTimeMs = response['reasoningTimeMs'];
        await saveMessage(aiMsg);
      } catch (e) {
        aiMsg.content = '请求失败: $e';
        await saveMessage(aiMsg);
      }
    }
    notifyListeners();
  }


  // 本地存取
  Future<void> _loadFromLocal() async {
    if (_initialized) return;
    _initialized = true;
    
    final chats = await isar.chatSessions.where().sortByLastUpdatedDesc().findAll();
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