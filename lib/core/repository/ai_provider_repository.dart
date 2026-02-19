import 'package:isar/isar.dart';
import '../models/chat_session.dart';
import '../models/message.dart';

/// ChatRepository 数据仓库。
class ChatRepository {
  final Isar isar;

  ChatRepository(this.isar);

  // 会话
  Future<List<ChatSession>> getChats() async {
    return await isar.chatSessions.where().findAll();
  }

  Future<ChatSession?> getChatById(int id) async {
    return await isar.chatSessions.get(id);
  }

  Future<void> saveChat(ChatSession chat) async {
    await isar.writeTxn(() async {
      await isar.chatSessions.put(chat);
    });
  }

  Future<void> deleteChat(int id) async {
    await isar.writeTxn(() async {
      await isar.chatSessions.delete(id);
    });
  }

  // 消息
  Future<List<Message>> getMessages(int chatId) async {
    return await isar.messages
        .filter()
        .chatIdEqualTo(chatId)
        .sortByTimestamp()
        .findAll();
  }

  Future<void> saveMessages(int chatId, List<Message> messages) async {
    await isar.writeTxn(() async {
      for (var msg in messages) {
        msg.chatId = chatId;
        await isar.messages.put(msg);
      }
    });
  }

  Future<void> addMessage(Message msg) async {
    await isar.writeTxn(() async {
      await isar.messages.put(msg);
    });
  }

  Stream<List<Message>> watchMessages(int chatId) {
    return isar.messages
        .filter()
        .chatIdEqualTo(chatId)
        .watch(fireImmediately: true);
  }
}
