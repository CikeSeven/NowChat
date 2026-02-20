import 'package:isar/isar.dart';

import '../models/chat_session.dart';
import '../models/message.dart';

/// 会话与消息仓库（Isar 访问层）。
///
/// 说明：
/// - 当前文件名为 `ai_provider_repository.dart`，但实际承载的是会话/消息读写。
/// - 上层 Provider 通过该仓库隔离数据库细节，避免在业务层直接操作查询对象。
class ChatRepository {
  /// Isar 数据库实例。
  final Isar isar;

  ChatRepository(this.isar);

  /// 读取全部会话。
  Future<List<ChatSession>> getChats() async {
    return await isar.chatSessions.where().findAll();
  }

  /// 根据会话 ID 读取单个会话。
  Future<ChatSession?> getChatById(int id) async {
    return await isar.chatSessions.get(id);
  }

  /// 保存或更新会话。
  Future<void> saveChat(ChatSession chat) async {
    await isar.writeTxn(() async {
      await isar.chatSessions.put(chat);
    });
  }

  /// 删除会话。
  ///
  /// 注意：该方法只删除会话实体，关联消息清理由上层策略控制。
  Future<void> deleteChat(int id) async {
    await isar.writeTxn(() async {
      await isar.chatSessions.delete(id);
    });
  }

  /// 读取指定会话的消息，并按时间正序返回。
  Future<List<Message>> getMessages(int chatId) async {
    return await isar.messages
        .filter()
        .chatIdEqualTo(chatId)
        .sortByTimestamp()
        .findAll();
  }

  /// 批量保存消息到指定会话。
  ///
  /// 保存前会统一覆盖每条消息的 [chatId]，确保消息归属正确。
  Future<void> saveMessages(int chatId, List<Message> messages) async {
    await isar.writeTxn(() async {
      for (final msg in messages) {
        msg.chatId = chatId;
        await isar.messages.put(msg);
      }
    });
  }

  /// 追加单条消息。
  Future<void> addMessage(Message msg) async {
    await isar.writeTxn(() async {
      await isar.messages.put(msg);
    });
  }

  /// 监听会话消息变化（包含首次立即推送）。
  Stream<List<Message>> watchMessages(int chatId) {
    return isar.messages
        .filter()
        .chatIdEqualTo(chatId)
        .watch(fireImmediately: true);
  }
}
