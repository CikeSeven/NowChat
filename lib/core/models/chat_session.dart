import 'package:isar/isar.dart';

part 'chat_session.g.dart';

@collection
class ChatSession {
  Id id = Isar.autoIncrement;
  late String title;
  String? providerId;
  String? model;
  String? systemPrompt;
  double temperature = 0.7;
  double topP = 1.0;
  int maxTokens = 0;
  int maxConversationTurns = 50;
  bool isStreaming = true;
  bool isGenerating = true;
  late final DateTime createdAt;
  late final DateTime lastUpdated;

  ChatSession({
    required this.title,
    this.providerId,
    this.model,
    this.systemPrompt,
    this.temperature = 0.7,
    this.topP = 1.0,
    this.maxTokens = 0,
    this.maxConversationTurns = 50,
    this.isStreaming = true,
    this.isGenerating = true,
    required this.createdAt,
    required this.lastUpdated,
  });

  void updateConfig({
    String? providerId,
    String? model,
    String? systemPrompt,
    double? temperature,
    double? topP,
    int? maxTokens,
    int? maxConversationTurns,
    bool? isStreaming,
    bool? isGenerating,
    DateTime? lastUpdated,
  }) {
    if (providerId != null) this.providerId = providerId;
    if (model != null) this.model = model;
    if (systemPrompt != null) this.systemPrompt = systemPrompt;
    if (temperature != null) this.temperature = temperature;
    if (topP != null) this.topP = topP;
    if (maxTokens != null) this.maxTokens = maxTokens;
    if (maxConversationTurns != null) {
      this.maxConversationTurns = maxConversationTurns;
    }
    if (isStreaming != null) this.isStreaming = isStreaming;
    if (isGenerating != null) this.isGenerating = isGenerating;
    if (lastUpdated != null) this.lastUpdated = lastUpdated;
  }

  ChatSession copyWith({
    String? title,
    String? providerId,
    String? model,
    String? systemPrompt,
    double? temperature,
    double? topP,
    int? maxTokens,
    int? maxConversationTurns,
    bool? isStreaming,
    bool? isGenerating,
    DateTime? lastUpdated,
  }) {
    return ChatSession(
      title: title ?? this.title,
      providerId: providerId ?? this.providerId,
      model: model ?? this.model,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      maxTokens: maxTokens ?? this.maxTokens,
      maxConversationTurns: maxConversationTurns ?? this.maxConversationTurns,
      isStreaming: isStreaming ?? this.isStreaming,
      createdAt: createdAt,
      isGenerating: isGenerating ?? this.isGenerating,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'providerId': providerId,
    'model': model,
    'systemPrompt': systemPrompt,
    'temperature': temperature,
    'topP': topP,
    'maxTokens': maxTokens,
    'maxConversationTurns': maxConversationTurns,
    'isStreaming': isStreaming,
    'isGenerating': isGenerating,
    "lastUpdated": lastUpdated.toIso8601String(),
  };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
    title: json['title'],
    providerId: json['providerId'],
    model: json['model'],
    systemPrompt: json['systemPrompt']?.toString(),
    temperature: (json['temperature'] ?? 0.7).toDouble(),
    topP: (json['topP'] ?? 1.0).toDouble(),
    maxTokens: json['maxTokens'] ?? 0,
    maxConversationTurns: json['maxConversationTurns'] ?? 50,
    isStreaming: json['isStreaming'] as bool? ?? true,
    isGenerating: json['isGenerating'] as bool? ?? true,
    createdAt: DateTime.parse(json['createdAt']),
    lastUpdated: DateTime.parse(json['lastUpdated']),
  );
}
