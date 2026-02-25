import 'package:shared_preferences/shared_preferences.dart';

/// 生图工具配置快照（供核心运行时读取）。
class ImageToolSettingsSnapshot {
  /// 是否向聊天模型暴露图片工具。
  final bool exposeImageToolsToChat;

  /// 默认生图模型（text-to-image）。
  final String? generationProviderId;
  final String? generationModel;
  final String generationSize;
  final int generationCount;

  /// 默认图片编辑模型（image-to-image）。
  final String? editProviderId;
  final String? editModel;
  final String editSize;

  const ImageToolSettingsSnapshot({
    required this.exposeImageToolsToChat,
    required this.generationProviderId,
    required this.generationModel,
    required this.generationSize,
    required this.generationCount,
    required this.editProviderId,
    required this.editModel,
    required this.editSize,
  });
}

/// 生图工具设置存储访问层。
///
/// 说明：
/// - 该类位于核心层，避免工具运行时依赖 UI Provider。
/// - key 需与 SettingsProvider 保持一致。
class ImageToolSettingsStore {
  static const _exposeImageToolsToChatKey = 'expose_image_tools_to_chat';
  static const _defaultImageGenerationProviderIdKey =
      'default_image_generation_provider_id';
  static const _defaultImageGenerationModelKey =
      'default_image_generation_model';
  static const _defaultImageGenerateSizeKey = 'default_image_generate_size';
  static const _defaultImageGenerateCountKey = 'default_image_generate_count';
  static const _defaultImageEditProviderIdKey = 'default_image_edit_provider_id';
  static const _defaultImageEditModelKey = 'default_image_edit_model';
  static const _defaultImageEditSizeKey = 'default_image_edit_size';

  /// 读取当前生图工具设置快照。
  static Future<ImageToolSettingsSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    final genProvider = _normalize(
      prefs.getString(_defaultImageGenerationProviderIdKey),
    );
    final genModel = _normalize(prefs.getString(_defaultImageGenerationModelKey));
    final genSize =
        _normalizeImageSize(prefs.getString(_defaultImageGenerateSizeKey)) ??
        '1024x1024';
    final genCount = _normalizeGenerateCount(
      prefs.getInt(_defaultImageGenerateCountKey),
    );
    final editProvider = _normalize(
      prefs.getString(_defaultImageEditProviderIdKey),
    );
    final editModel = _normalize(prefs.getString(_defaultImageEditModelKey));
    // 尺寸配置统一：优先使用默认生图尺寸，旧 key 仅用于历史兜底。
    final editSize =
        genSize ??
        _normalizeImageSize(prefs.getString(_defaultImageEditSizeKey)) ??
        '1024x1024';
    return ImageToolSettingsSnapshot(
      exposeImageToolsToChat:
          prefs.getBool(_exposeImageToolsToChatKey) ?? false,
      generationProviderId: genProvider,
      generationModel: genModel,
      generationSize: genSize,
      generationCount: genCount,
      editProviderId: editProvider,
      editModel: editModel,
      editSize: editSize,
    );
  }

  /// 规范化可选字符串。
  static String? _normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  /// 规范化尺寸字符串。
  static String? _normalizeImageSize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  /// 规范化生图数量，仅允许 1/2/4。
  static int _normalizeGenerateCount(int? value) {
    switch (value) {
      case 2:
      case 4:
        return value!;
      case 1:
      default:
        return 1;
    }
  }
}
