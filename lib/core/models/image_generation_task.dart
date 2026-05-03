import 'package:now_chat/core/models/ai_provider_config.dart';
import 'package:uuid/uuid.dart';

/// 生图任务模式。
enum ImageGenerationTaskMode {
  /// 文本生成图片。
  generate,

  /// 基于已有图片编辑。
  edit,
}

/// 生图任务状态。
enum ImageGenerationTaskStatus {
  /// 已入队，等待调度。
  queued,

  /// 正在执行中。
  running,

  /// 执行完成。
  succeeded,

  /// 执行失败。
  failed,

  /// 已取消。
  canceled,
}

/// 工作台生图队列任务。
///
/// 说明：
/// - 任务包含执行所需的完整快照，避免设置变更影响已排队任务。
/// - 任务作为持久化实体，支持应用重启后恢复执行。
class ImageGenerationTask {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final ImageGenerationTaskMode mode;
  final ImageGenerationTaskStatus status;
  final String providerId;
  final String model;
  final ImageRequestMode requestMode;
  final String? size;
  final int requestCount;
  final String prompt;
  final String? sourceImagePath;
  final List<String> resultImageUris;
  final String? revisedPrompt;
  final String? errorMessage;
  final int retryCount;

  const ImageGenerationTask({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.startedAt,
    required this.finishedAt,
    required this.mode,
    required this.status,
    required this.providerId,
    required this.model,
    required this.requestMode,
    required this.size,
    required this.requestCount,
    required this.prompt,
    required this.sourceImagePath,
    required this.resultImageUris,
    required this.revisedPrompt,
    required this.errorMessage,
    required this.retryCount,
  });

  /// 新建排队任务。
  factory ImageGenerationTask.createQueued({
    required ImageGenerationTaskMode mode,
    required String providerId,
    required String model,
    required ImageRequestMode requestMode,
    required String prompt,
    String? sourceImagePath,
    String? size,
    int requestCount = 1,
  }) {
    final now = DateTime.now();
    final normalizedCount =
        (requestCount <= 1)
            ? 1
            : (requestCount == 2 ? 2 : (requestCount == 4 ? 4 : 1));
    return ImageGenerationTask(
      id: const Uuid().v4(),
      createdAt: now,
      updatedAt: now,
      startedAt: null,
      finishedAt: null,
      mode: mode,
      status: ImageGenerationTaskStatus.queued,
      providerId: providerId,
      model: model,
      requestMode: requestMode,
      size: size?.trim().isEmpty == true ? null : size?.trim(),
      requestCount: mode == ImageGenerationTaskMode.edit ? 1 : normalizedCount,
      prompt: prompt,
      sourceImagePath:
          sourceImagePath?.trim().isEmpty == true
              ? null
              : sourceImagePath?.trim(),
      resultImageUris: const <String>[],
      revisedPrompt: null,
      errorMessage: null,
      retryCount: 0,
    );
  }

  bool get isTerminal {
    return status == ImageGenerationTaskStatus.succeeded ||
        status == ImageGenerationTaskStatus.failed ||
        status == ImageGenerationTaskStatus.canceled;
  }

  ImageGenerationTask copyWith({
    DateTime? updatedAt,
    DateTime? startedAt,
    DateTime? finishedAt,
    ImageGenerationTaskStatus? status,
    String? providerId,
    String? model,
    ImageRequestMode? requestMode,
    String? size,
    int? requestCount,
    String? prompt,
    String? sourceImagePath,
    List<String>? resultImageUris,
    String? revisedPrompt,
    String? errorMessage,
    int? retryCount,
  }) {
    return ImageGenerationTask(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      mode: mode,
      status: status ?? this.status,
      providerId: providerId ?? this.providerId,
      model: model ?? this.model,
      requestMode: requestMode ?? this.requestMode,
      size: size ?? this.size,
      requestCount: requestCount ?? this.requestCount,
      prompt: prompt ?? this.prompt,
      sourceImagePath: sourceImagePath ?? this.sourceImagePath,
      resultImageUris: resultImageUris ?? this.resultImageUris,
      revisedPrompt: revisedPrompt ?? this.revisedPrompt,
      errorMessage: errorMessage ?? this.errorMessage,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'startedAt': startedAt?.toIso8601String(),
      'finishedAt': finishedAt?.toIso8601String(),
      'mode': mode.name,
      'status': status.name,
      'providerId': providerId,
      'model': model,
      'requestMode': requestMode.name,
      'size': size,
      'requestCount': requestCount,
      'prompt': prompt,
      'sourceImagePath': sourceImagePath,
      'resultImageUris': resultImageUris,
      'revisedPrompt': revisedPrompt,
      'errorMessage': errorMessage,
      'retryCount': retryCount,
    };
  }

  factory ImageGenerationTask.fromJson(Map<String, dynamic> json) {
    final mode = ImageGenerationTaskMode.values.firstWhere(
      (item) => item.name == json['mode']?.toString(),
      orElse: () => ImageGenerationTaskMode.generate,
    );
    final status = ImageGenerationTaskStatus.values.firstWhere(
      (item) => item.name == json['status']?.toString(),
      orElse: () => ImageGenerationTaskStatus.queued,
    );
    final requestMode = ImageRequestMode.values.firstWhere(
      (item) => item.name == json['requestMode']?.toString(),
      orElse: () => ImageRequestMode.inheritProvider,
    );
    return ImageGenerationTask(
      id: json['id']?.toString() ?? const Uuid().v4(),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      startedAt: DateTime.tryParse(json['startedAt']?.toString() ?? ''),
      finishedAt: DateTime.tryParse(json['finishedAt']?.toString() ?? ''),
      mode: mode,
      status: status,
      providerId: json['providerId']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      requestMode: requestMode,
      size: json['size']?.toString(),
      requestCount: (json['requestCount'] as num?)?.toInt() ?? 1,
      prompt: json['prompt']?.toString() ?? '',
      sourceImagePath: json['sourceImagePath']?.toString(),
      resultImageUris:
          (json['resultImageUris'] as List?)
              ?.map((item) => item.toString())
              .toList() ??
          const <String>[],
      revisedPrompt: json['revisedPrompt']?.toString(),
      errorMessage: json['errorMessage']?.toString(),
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
    );
  }
}
