import 'package:isar/isar.dart';

part 'message.g.dart';

@collection
/// Message 类型定义。
class Message {
  Id isarId = Isar.autoIncrement;
  late int chatId;
  late String role;
  late String content;
  String? reasoning;
  int? reasoningTimeMs;
  List<String>? imagePaths;
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
