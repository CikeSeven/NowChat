import 'package:isar/isar.dart';

part 'chat_session.g.dart';

@collection
/// 会话实体模型。
///
/// 保存单个会话的基础信息、默认模型配置与会话级推理参数。
class ChatSession {
  /// Isar 主键（自增）。
  Id id = Isar.autoIncrement;

  /// 会话标题（列表主显示字段）。
  late String title;

  /// 默认提供方 ID（可为空，表示未绑定）。
  String? providerId;

  /// 默认模型名（可为空，表示未绑定）。
  String? model;

  /// 会话级系统提示词，会拼接到请求顶部。
  String? systemPrompt;

  /// 温度参数，数值越高越发散。
  double temperature = 0.7;

  /// nucleus sampling 参数。
  double topP = 1.0;

  /// 输出 token 上限；0 表示不主动传递该参数。
  int maxTokens = 0;

  /// 会话上下文最大轮次（按“用户+AI”为 1 轮）。
  int maxConversationTurns = 50;

  /// 是否允许模型调用工具。
  bool toolCallingEnabled = true;

  /// 单次请求允许的工具调用上限。
  int maxToolCalls = 5;

  /// 是否默认使用流式输出。
  bool isStreaming = true;

  /// 是否允许“继续生成”能力。
  bool isGenerating = true;

  /// 会话创建时间。
  late final DateTime createdAt;

  /// 会话最后更新时间。
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
    this.toolCallingEnabled = true,
    this.maxToolCalls = 5,
    this.isStreaming = true,
    this.isGenerating = true,
    required this.createdAt,
    required this.lastUpdated,
  });

  /// 原地更新配置：仅覆盖非 null 字段。
  void updateConfig({
    String? providerId,
    String? model,
    String? systemPrompt,
    double? temperature,
    double? topP,
    int? maxTokens,
    int? maxConversationTurns,
    bool? toolCallingEnabled,
    int? maxToolCalls,
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
    if (toolCallingEnabled != null) {
      this.toolCallingEnabled = toolCallingEnabled;
    }
    if (maxToolCalls != null) {
      this.maxToolCalls = maxToolCalls;
    }
    if (isStreaming != null) this.isStreaming = isStreaming;
    if (isGenerating != null) this.isGenerating = isGenerating;
    if (lastUpdated != null) this.lastUpdated = lastUpdated;
  }

  /// 复制会话并返回新实例，不修改当前对象。
  ChatSession copyWith({
    String? title,
    String? providerId,
    String? model,
    String? systemPrompt,
    double? temperature,
    double? topP,
    int? maxTokens,
    int? maxConversationTurns,
    bool? toolCallingEnabled,
    int? maxToolCalls,
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
      toolCallingEnabled: toolCallingEnabled ?? this.toolCallingEnabled,
      maxToolCalls: maxToolCalls ?? this.maxToolCalls,
      isStreaming: isStreaming ?? this.isStreaming,
      createdAt: createdAt,
      isGenerating: isGenerating ?? this.isGenerating,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  /// 序列化为 JSON（用于备份导入导出）。
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
    'toolCallingEnabled': toolCallingEnabled,
    'maxToolCalls': maxToolCalls,
    'isStreaming': isStreaming,
    'isGenerating': isGenerating,
    "lastUpdated": lastUpdated.toIso8601String(),
  };

  /// 从 JSON 反序列化会话对象。
  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
    title: json['title'],
    providerId: json['providerId'],
    model: json['model'],
    systemPrompt: json['systemPrompt']?.toString(),
    temperature: (json['temperature'] ?? 0.7).toDouble(),
    topP: (json['topP'] ?? 1.0).toDouble(),
    maxTokens: json['maxTokens'] ?? 0,
    maxConversationTurns: json['maxConversationTurns'] ?? 50,
    toolCallingEnabled: json['toolCallingEnabled'] as bool? ?? true,
    maxToolCalls: json['maxToolCalls'] ?? 5,
    isStreaming: json['isStreaming'] as bool? ?? true,
    isGenerating: json['isGenerating'] as bool? ?? true,
    createdAt: DateTime.parse(json['createdAt']),
    lastUpdated: DateTime.parse(json['lastUpdated']),
  );
}
