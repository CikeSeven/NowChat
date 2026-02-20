import 'package:isar/isar.dart';

part 'message.g.dart';

@collection
/// 单条消息实体。
///
/// 同时用于：
/// - 用户输入消息
/// - 助手回复消息
/// - 含图片/推理片段的消息展示
class Message {
  /// Isar 主键（自增）。
  Id isarId = Isar.autoIncrement;

  /// 关联会话 ID。
  late int chatId;

  /// 角色标识：通常为 `user`/`assistant`/`system`。
  late String role;

  /// 消息正文。
  late String content;

  /// 模型“思考内容”（如 reasoning）。
  String? reasoning;

  /// 思考耗时（毫秒）。
  int? reasoningTimeMs;

  /// 关联图片路径列表（本地路径）。
  List<String>? imagePaths;

  /// 消息时间戳。
  late final DateTime timestamp;

  Message({
    required this.chatId,
    required this.role,
    required this.content,
    this.reasoning,
    this.reasoningTimeMs,
    this.imagePaths,
    required this.timestamp,
  });

  /// 序列化为 JSON（用于备份导入导出）。
  Map<String, dynamic> toJson() => {
    'id': isarId,
    'chatId': chatId,
    'role': role,
    'content': content,
    'reasoning': reasoning,
    'reasoningTimeMs': reasoningTimeMs,
    'imagePaths': imagePaths,
    'timestamp': timestamp.toIso8601String(),
  };

  /// 从 JSON 反序列化消息。
  factory Message.fromJson(Map<String, dynamic> json) => Message(
    chatId: json['chatId'],
    role: json['role'],
    content: json['content'],
    reasoning: json['reasoning'],
    reasoningTimeMs: json['reasoningTimeMs'],
    imagePaths:
        (json['imagePaths'] as List?)?.map((e) => e.toString()).toList(),
    timestamp: DateTime.parse(json['timestamp']),
  );
}
