import 'package:uuid/uuid.dart';

/// 可复用的智能体配置（提示词模板 + 可选模型参数覆盖）。
class AgentProfile {
  /// 全局唯一 ID。
  final String id;

  /// 智能体名称。
  String name;

  /// 智能体说明（列表展示）。
  String summary;

  /// 智能体提示词（作为 system prompt）。
  String prompt;

  /// 绑定提供方 ID（为空则回退到默认设置）。
  String? providerId;

  /// 绑定模型名（为空则回退到默认设置）。
  String? model;

  /// 可选温度参数覆盖。
  double? temperature;

  /// 可选 top_p 参数覆盖。
  double? topP;

  /// 可选最大输出 token 参数覆盖。
  int? maxTokens;

  /// 可选流式开关覆盖。
  bool? isStreaming;

  /// 创建时间。
  DateTime createdAt;

  /// 最近更新时间。
  DateTime updatedAt;

  AgentProfile({
    required this.id,
    required this.name,
    required this.summary,
    required this.prompt,
    this.providerId,
    this.model,
    this.temperature,
    this.topP,
    this.maxTokens,
    this.isStreaming,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 创建新的智能体配置。
  factory AgentProfile.create({
    required String name,
    required String summary,
    required String prompt,
    String? providerId,
    String? model,
    double? temperature,
    double? topP,
    int? maxTokens,
    bool? isStreaming,
  }) {
    final now = DateTime.now();
    return AgentProfile(
      id: const Uuid().v4(),
      name: name.trim(),
      summary: summary.trim(),
      prompt: prompt.trim(),
      providerId: _normalizeNullable(providerId),
      model: _normalizeNullable(model),
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
      isStreaming: isStreaming,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// 复制并更新部分字段。
  AgentProfile copyWith({
    String? name,
    String? summary,
    String? prompt,
    String? providerId,
    String? model,
    double? temperature,
    double? topP,
    int? maxTokens,
    bool? isStreaming,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AgentProfile(
      id: id,
      name: (name ?? this.name).trim(),
      summary: (summary ?? this.summary).trim(),
      prompt: (prompt ?? this.prompt).trim(),
      providerId: _normalizeNullable(providerId ?? this.providerId),
      model: _normalizeNullable(model ?? this.model),
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      maxTokens: maxTokens ?? this.maxTokens,
      isStreaming: isStreaming ?? this.isStreaming,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 将当前配置应用编辑更新。
  void applyUpdate({
    required String name,
    required String summary,
    required String prompt,
    String? providerId,
    String? model,
    double? temperature,
    double? topP,
    int? maxTokens,
    bool? isStreaming,
  }) {
    this.name = name.trim();
    this.summary = summary.trim();
    this.prompt = prompt.trim();
    this.providerId = _normalizeNullable(providerId);
    this.model = _normalizeNullable(model);
    this.temperature = temperature;
    this.topP = topP;
    this.maxTokens = maxTokens;
    this.isStreaming = isStreaming;
    updatedAt = DateTime.now();
  }

  /// JSON 序列化。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'summary': summary,
      'prompt': prompt,
      'providerId': providerId,
      'model': model,
      'temperature': temperature,
      'topP': topP,
      'maxTokens': maxTokens,
      'isStreaming': isStreaming,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// JSON 反序列化。
  factory AgentProfile.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return AgentProfile(
      id:
          (json['id']?.toString().trim().isNotEmpty ?? false)
              ? json['id'].toString()
              : const Uuid().v4(),
      name: (json['name'] ?? '').toString().trim(),
      summary: (json['summary'] ?? '').toString().trim(),
      prompt: (json['prompt'] ?? '').toString().trim(),
      providerId: _normalizeNullable(json['providerId']?.toString()),
      model: _normalizeNullable(json['model']?.toString()),
      temperature: _toDoubleOrNull(json['temperature']),
      topP: _toDoubleOrNull(json['topP']),
      maxTokens: _toIntOrNull(json['maxTokens']),
      isStreaming:
          json['isStreaming'] is bool ? json['isStreaming'] as bool : null,
      createdAt: _toDateTimeOrDefault(json['createdAt'], now),
      updatedAt: _toDateTimeOrDefault(json['updatedAt'], now),
    );
  }

  static String? _normalizeNullable(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized;
  }

  static double? _toDoubleOrNull(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.trim());
    return null;
  }

  static int? _toIntOrNull(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  static DateTime _toDateTimeOrDefault(dynamic raw, DateTime fallback) {
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return fallback;
  }
}
