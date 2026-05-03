import 'package:uuid/uuid.dart';

import 'ai_provider_config.dart';

/// 工作台“生图”页面的独立历史记录。
class ImageGenerationRecord {
  /// 唯一 ID，用于列表去重与排序稳定性。
  final String id;

  /// 发起时间。
  final DateTime createdAt;

  /// 选中的 Provider 与模型。
  final String providerId;
  final String model;

  /// 模型类型（生图/图片编辑）。
  final ModelType modelType;

  /// 本次请求提示词。
  final String prompt;

  /// 生成结果图地址（本地路径或远程 URL）。
  final List<String> imageUris;

  /// 图片编辑时的原图路径（可选）。
  final String? sourceImagePath;

  /// 模型修订后的提示词（若接口返回）。
  final String? revisedPrompt;

  ImageGenerationRecord({
    required this.id,
    required this.createdAt,
    required this.providerId,
    required this.model,
    required this.modelType,
    required this.prompt,
    required this.imageUris,
    this.sourceImagePath,
    this.revisedPrompt,
  });

  /// 创建新记录（自动生成 ID）。
  factory ImageGenerationRecord.create({
    required String providerId,
    required String model,
    required ModelType modelType,
    required String prompt,
    required List<String> imageUris,
    String? sourceImagePath,
    String? revisedPrompt,
  }) {
    return ImageGenerationRecord(
      id: const Uuid().v4(),
      createdAt: DateTime.now(),
      providerId: providerId,
      model: model,
      modelType: modelType,
      prompt: prompt,
      imageUris: imageUris,
      sourceImagePath: sourceImagePath,
      revisedPrompt: revisedPrompt,
    );
  }

  /// JSON 序列化。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'providerId': providerId,
      'model': model,
      'modelType': modelType.name,
      'prompt': prompt,
      'imageUris': imageUris,
      'sourceImagePath': sourceImagePath,
      'revisedPrompt': revisedPrompt,
    };
  }

  /// JSON 反序列化（对历史数据做安全回退）。
  factory ImageGenerationRecord.fromJson(Map<String, dynamic> json) {
    final rawModelType = json['modelType']?.toString().trim() ?? '';
    final modelType = ModelType.values.firstWhere(
      (value) => value.name == rawModelType,
      orElse: () => ModelType.imageGeneration,
    );
    final imageUris =
        (json['imageUris'] as List?)
            ?.map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList() ??
        <String>[];
    return ImageGenerationRecord(
      id: json['id']?.toString() ?? const Uuid().v4(),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      providerId: json['providerId']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      modelType: modelType,
      prompt: json['prompt']?.toString() ?? '',
      imageUris: imageUris,
      sourceImagePath: json['sourceImagePath']?.toString(),
      revisedPrompt: json['revisedPrompt']?.toString(),
    );
  }
}
