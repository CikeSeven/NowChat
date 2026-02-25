import 'package:uuid/uuid.dart';

/// 内置与兼容提供方类型。
enum ProviderType {
  openai,
  gemini,
  claude,
  ollama,
  deepseek,

  /// 兼容 OpenAI Chat Completions 协议的第三方服务。
  openaiCompatible;

  /// 提供方默认显示名称。
  String get defaultName {
    switch (this) {
      case ProviderType.openai:
        return 'OpenAI';
      case ProviderType.gemini:
        return 'Gemini';
      case ProviderType.claude:
        return 'Claude';
      case ProviderType.ollama:
        return 'Ollama';
      case ProviderType.deepseek:
        return 'DeepSeek';
      case ProviderType.openaiCompatible:
        return 'OpenAI 兼容';
    }
  }

  /// 提供方默认基础地址。
  String get defaultBaseUrl {
    switch (this) {
      case ProviderType.openai:
        return 'https://api.openai.com/v1';
      case ProviderType.gemini:
        return 'https://generativelanguage.googleapis.com';
      case ProviderType.claude:
        return 'https://api.anthropic.com';
      case ProviderType.ollama:
        return 'http://localhost:11434/v1';
      case ProviderType.deepseek:
        return 'https://api.deepseek.com/v1';
      case ProviderType.openaiCompatible:
        return '';
    }
  }

  /// 提供方默认请求路径。
  String get defaultPath {
    switch (this) {
      case ProviderType.deepseek:
      case ProviderType.ollama:
      case ProviderType.openai:
        return '/chat/completions';
      case ProviderType.gemini:
        return '/v1beta/models/[model]:generateContent';
      case ProviderType.claude:
        return '/v1/messages';
      case ProviderType.openaiCompatible:
        return '/chat/completions';
    }
  }

  /// 是否允许用户在 UI 编辑路径。
  bool get allowEditPath {
    switch (this) {
      case ProviderType.openai:
      case ProviderType.claude:
      case ProviderType.gemini:
      case ProviderType.deepseek:
      case ProviderType.ollama:
        return false;
      case ProviderType.openaiCompatible:
        return true;
    }
  }

  /// 当前提供方是否必须提供 API Key。
  bool get requiresApiKey {
    return true;
  }
}

/// 请求协议模式。
enum RequestMode {
  openaiChat,
  geminiGenerateContent,
  claudeMessages;

  /// 在 UI 中显示的协议标签。
  String get label {
    switch (this) {
      case RequestMode.openaiChat:
        return 'OpenAI Chat Completions';
      case RequestMode.geminiGenerateContent:
        return 'Gemini GenerateContent';
      case RequestMode.claudeMessages:
        return 'Claude Messages';
    }
  }

  /// 是否支持流式响应。
  bool get supportsStreaming {
    switch (this) {
      case RequestMode.openaiChat:
      case RequestMode.geminiGenerateContent:
      case RequestMode.claudeMessages:
        return true;
    }
  }

  /// 当前协议默认路径模板。
  String get defaultPath {
    switch (this) {
      case RequestMode.openaiChat:
        return '/chat/completions';
      case RequestMode.geminiGenerateContent:
        return '/v1beta/models/[model]:generateContent';
      case RequestMode.claudeMessages:
        return '/v1/messages';
    }
  }
}

/// 模型类型，用于区分文本模型与图像模型能力场景。
enum ModelType {
  /// 常规文本对话模型。
  text,

  /// 文生图模型（text-to-image）。
  imageGeneration,

  /// 图片编辑模型（image-to-image）。
  imageEdit;

  /// 中文显示名称。
  String get label {
    switch (this) {
      case ModelType.text:
        return '文本模型';
      case ModelType.imageGeneration:
        return '生图模型';
      case ModelType.imageEdit:
        return '图片编辑模型';
    }
  }
}

/// 图像请求协议模式。
///
/// 说明：
/// - `inheritProvider` 表示按 Provider 默认协议推断（当前主要用于 OpenAI 兼容链路）。
/// - 其余值表示模型级显式覆盖。
enum ImageRequestMode {
  /// 继承 Provider 默认请求语义。
  inheritProvider,

  /// OpenAI Images Generate 协议。
  openaiImagesGenerate,

  /// OpenAI Images Edit 协议。
  openaiImagesEdit;

  /// 中文显示名称。
  String get label {
    switch (this) {
      case ImageRequestMode.inheritProvider:
        return '继承 Provider 默认协议';
      case ImageRequestMode.openaiImagesGenerate:
        return 'OpenAI Images Generate';
      case ImageRequestMode.openaiImagesEdit:
        return 'OpenAI Images Edit';
    }
  }
}

/// 单个模型可选能力配置。
class ModelFeatureOptions {
  static const Object _unset = Object();

  /// 是否支持视觉输入。
  final bool supportsVision;

  /// 是否支持工具调用。
  final bool supportsTools;

  /// 模型类型（文本/生图/图片编辑）。
  final ModelType modelType;

  /// 图像请求协议（可覆盖 Provider 默认）。
  final ImageRequestMode imageRequestMode;

  /// 模型级图像接口 Base URL 覆盖（可选）。
  final String? imageBaseUrl;

  /// 模型级生图请求路径覆盖（可选）。
  final String? imageGeneratePath;

  /// 模型级图片编辑请求路径覆盖（可选）。
  final String? imageEditPath;

  const ModelFeatureOptions({
    this.supportsVision = false,
    this.supportsTools = false,
    this.modelType = ModelType.text,
    this.imageRequestMode = ImageRequestMode.inheritProvider,
    this.imageBaseUrl,
    this.imageGeneratePath,
    this.imageEditPath,
  });

  /// 是否至少开启了一项能力。
  bool get hasAnyCapability => supportsVision || supportsTools;

  /// 是否包含任一图像路由覆盖字段。
  bool get hasImageRouteOverrides =>
      (imageBaseUrl ?? '').trim().isNotEmpty ||
      (imageGeneratePath ?? '').trim().isNotEmpty ||
      (imageEditPath ?? '').trim().isNotEmpty;

  /// 是否包含任一图像相关配置（类型、协议、路由覆盖）。
  bool get hasAnyImageConfig =>
      modelType != ModelType.text ||
      imageRequestMode != ImageRequestMode.inheritProvider ||
      hasImageRouteOverrides;

  /// 返回带有部分字段变更的新实例。
  ModelFeatureOptions copyWith({
    bool? supportsVision,
    bool? supportsTools,
    ModelType? modelType,
    ImageRequestMode? imageRequestMode,
    Object? imageBaseUrl = _unset,
    Object? imageGeneratePath = _unset,
    Object? imageEditPath = _unset,
  }) {
    final nextImageBaseUrl =
        imageBaseUrl == _unset
            ? this.imageBaseUrl
            : _normalizeOptional(imageBaseUrl as String?);
    final nextImageGeneratePath =
        imageGeneratePath == _unset
            ? this.imageGeneratePath
            : _normalizePath(imageGeneratePath as String?);
    final nextImageEditPath =
        imageEditPath == _unset
            ? this.imageEditPath
            : _normalizePath(imageEditPath as String?);
    return ModelFeatureOptions(
      supportsVision: supportsVision ?? this.supportsVision,
      supportsTools: supportsTools ?? this.supportsTools,
      modelType: modelType ?? this.modelType,
      imageRequestMode: imageRequestMode ?? this.imageRequestMode,
      imageBaseUrl: nextImageBaseUrl,
      imageGeneratePath: nextImageGeneratePath,
      imageEditPath: nextImageEditPath,
    );
  }

  /// 序列化为 JSON。
  Map<String, dynamic> toJson() => {
    'supportsVision': supportsVision,
    'supportsTools': supportsTools,
    'modelType': modelType.name,
    'imageRequestMode': imageRequestMode.name,
    if ((imageBaseUrl ?? '').trim().isNotEmpty) 'imageBaseUrl': imageBaseUrl,
    if ((imageGeneratePath ?? '').trim().isNotEmpty)
      'imageGeneratePath': imageGeneratePath,
    if ((imageEditPath ?? '').trim().isNotEmpty) 'imageEditPath': imageEditPath,
  };

  /// 从动态对象解析能力配置，兼容多种历史字段名。
  static ModelFeatureOptions fromDynamic(dynamic raw) {
    if (raw is Map) {
      final supportsVision =
          raw['supportsVision'] == true ||
          raw['vision'] == true ||
          raw['multimodal'] == true;
      final supportsTools =
          raw['supportsTools'] == true ||
          raw['tools'] == true ||
          raw['functionCalling'] == true;
      final modelTypeRaw =
          raw['modelType']?.toString() ??
          raw['type']?.toString() ??
          raw['modelKind']?.toString();
      final imageModeRaw =
          raw['imageRequestMode']?.toString() ??
          raw['imageProtocol']?.toString() ??
          raw['imageMode']?.toString();
      final imageBaseUrlRaw =
          raw['imageBaseUrl']?.toString() ??
          raw['image_base_url']?.toString() ??
          raw['baseUrl']?.toString();
      final imageGeneratePathRaw =
          raw['imageGeneratePath']?.toString() ??
          raw['image_generate_path']?.toString() ??
          raw['imagesGeneratePath']?.toString();
      final imageEditPathRaw =
          raw['imageEditPath']?.toString() ??
          raw['image_edit_path']?.toString() ??
          raw['imagesEditPath']?.toString();
      return ModelFeatureOptions(
        supportsVision: supportsVision,
        supportsTools: supportsTools,
        modelType: _parseModelType(modelTypeRaw),
        imageRequestMode: _parseImageRequestMode(imageModeRaw),
        imageBaseUrl: _normalizeOptional(imageBaseUrlRaw),
        imageGeneratePath: _normalizePath(imageGeneratePathRaw),
        imageEditPath: _normalizePath(imageEditPathRaw),
      );
    }
    return const ModelFeatureOptions();
  }

  static String? _normalizeOptional(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized;
  }

  static String? _normalizePath(String? value) {
    final normalized = _normalizeOptional(value);
    if (normalized == null) return null;
    return normalized.startsWith('/') ? normalized : '/$normalized';
  }

  /// 解析模型类型，异常或未知值回退为文本模型。
  static ModelType _parseModelType(String? raw) {
    if (raw == null || raw.trim().isEmpty) return ModelType.text;
    final normalized = raw.trim().toLowerCase();
    for (final value in ModelType.values) {
      if (value.name.toLowerCase() == normalized) {
        return value;
      }
    }
    switch (normalized) {
      case 'image_generation':
      case 'image-generation':
      case 'image':
        return ModelType.imageGeneration;
      case 'image_edit':
      case 'image-edit':
      case 'imageeditor':
      case 'image_editor':
      case 'edit':
        return ModelType.imageEdit;
      default:
        return ModelType.text;
    }
  }

  /// 解析图像请求协议模式，未知值回退为继承 Provider。
  static ImageRequestMode _parseImageRequestMode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return ImageRequestMode.inheritProvider;
    }
    final normalized = raw.trim().toLowerCase();
    for (final value in ImageRequestMode.values) {
      if (value.name.toLowerCase() == normalized) {
        return value;
      }
    }
    switch (normalized) {
      case 'openai_images_generate':
      case 'openai-images-generate':
      case 'images_generate':
      case 'images-generate':
      case 'generate':
        return ImageRequestMode.openaiImagesGenerate;
      case 'openai_images_edit':
      case 'openai-images-edit':
      case 'images_edit':
      case 'images-edit':
      case 'edit':
        return ImageRequestMode.openaiImagesEdit;
      default:
        return ImageRequestMode.inheritProvider;
    }
  }
}

/// 用户配置的 AI 提供方实体。
class AIProviderConfig {
  /// 全局唯一 ID。
  final String id;

  /// 提供方显示名称。
  String name;

  /// 提供方类别。
  ProviderType type;

  /// 请求协议模式。
  RequestMode requestMode;

  /// 基础地址（例如 `https://api.openai.com`）。
  String? baseUrl;

  /// 请求路径（可包含 `[model]` 占位符）。
  String? urlPath;

  /// 鉴权密钥。
  String? apiKey;

  /// 该提供方可选模型列表。
  List<String> models;

  /// 模型备注（`模型名 -> 备注显示名`）。
  Map<String, String> modelRemarks;

  /// 模型能力配置（`模型名 -> 能力`）。
  Map<String, ModelFeatureOptions> modelCapabilities;

  AIProviderConfig({
    required this.id,
    required this.name,
    required this.type,
    this.requestMode = RequestMode.openaiChat,
    this.baseUrl,
    this.urlPath,
    this.apiKey,
    List<String>? models,
    Map<String, String>? modelRemarks,
    Map<String, ModelFeatureOptions>? modelCapabilities,
  }) : models = _normalizeModels(models),
       modelRemarks = _normalizeRemarks(
         remarks: modelRemarks,
         models: _normalizeModels(models),
       ),
       modelCapabilities = _normalizeCapabilities(
         capabilities: modelCapabilities,
         models: _normalizeModels(models),
       );

  /// 创建一个用于新建流程的空白配置。
  factory AIProviderConfig.newCustom() {
    return AIProviderConfig(
      id: const Uuid().v4(),
      name: '',
      type: ProviderType.openai,
      requestMode: RequestMode.openaiChat,
      baseUrl: null,
      urlPath: null,
      apiKey: null,
      models: [],
      modelRemarks: {},
      modelCapabilities: {},
    );
  }

  /// 按需更新当前配置。
  void updateConfig({
    String? name,
    ProviderType? type,
    RequestMode? requestMode,
    String? baseUrl,
    String? apiKey,
    String? urlPath,
    List<String>? models,
    Map<String, String>? modelRemarks,
    Map<String, ModelFeatureOptions>? modelCapabilities,
  }) {
    if (name != null && name.isNotEmpty) this.name = name;
    if (type != null) this.type = type;
    if (requestMode != null) this.requestMode = requestMode;
    if (baseUrl != null) this.baseUrl = baseUrl;
    if (apiKey != null) this.apiKey = apiKey;
    if (urlPath != null) this.urlPath = urlPath;
    if (models != null) {
      this.models = _normalizeModels(models);
      this.modelRemarks = _normalizeRemarks(
        remarks: this.modelRemarks,
        models: this.models,
      );
      this.modelCapabilities = _normalizeCapabilities(
        capabilities: this.modelCapabilities,
        models: this.models,
      );
    }
    if (modelRemarks != null) {
      this.modelRemarks = _normalizeRemarks(
        remarks: modelRemarks,
        models: this.models,
      );
    }
    if (modelCapabilities != null) {
      this.modelCapabilities = _normalizeCapabilities(
        capabilities: modelCapabilities,
        models: this.models,
      );
    }
  }

  /// 获取模型在 UI 的显示名（优先备注）。
  String displayNameForModel(String model) {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return model;
    final remark = modelRemarks[trimmed]?.trim();
    if (remark == null || remark.isEmpty) return trimmed;
    return remark;
  }

  /// 获取指定模型能力配置。
  ModelFeatureOptions featuresForModel(String model) {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return const ModelFeatureOptions();
    return modelCapabilities[trimmed] ?? const ModelFeatureOptions();
  }

  /// 序列化为 JSON。
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'requestMode': requestMode.name,
    'baseUrl': baseUrl,
    'urlPath': urlPath,
    'apiKey': apiKey,
    'models': models,
    'modelRemarks': modelRemarks,
    'modelCapabilities': modelCapabilities.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
  };

  /// 返回带有部分字段变更的新实例。
  AIProviderConfig copyWith({
    String? id,
    String? name,
    ProviderType? type,
    RequestMode? requestMode,
    String? baseUrl,
    String? urlPath,
    String? apiKey,
    List<String>? models,
    Map<String, String>? modelRemarks,
    Map<String, ModelFeatureOptions>? modelCapabilities,
  }) {
    return AIProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      requestMode: requestMode ?? this.requestMode,
      baseUrl: baseUrl ?? this.baseUrl,
      urlPath: urlPath ?? this.urlPath,
      apiKey: apiKey ?? this.apiKey,
      models: models ?? this.models,
      modelRemarks: modelRemarks ?? this.modelRemarks,
      modelCapabilities: modelCapabilities ?? this.modelCapabilities,
    );
  }

  /// 从 JSON 反序列化配置。
  factory AIProviderConfig.fromJson(Map<String, dynamic> json) =>
      AIProviderConfig(
        id: json['id'],
        name: json['name'],
        type: ProviderType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => ProviderType.openai,
        ),
        requestMode: inferRequestMode(
          type: ProviderType.values.firstWhere(
            (t) => t.name == json['type'],
            orElse: () => ProviderType.openai,
          ),
          baseUrl: json['baseUrl']?.toString(),
          urlPath: json['urlPath']?.toString(),
          requestModeName: json['requestMode']?.toString(),
        ),
        baseUrl: json['baseUrl'],
        urlPath: json['urlPath'],
        apiKey: json['apiKey'],
        models: _parseModels(json['models']),
        modelRemarks: _parseModelRemarks(
          rawRemarks: json['modelRemarks'],
          rawModels: json['models'],
        ),
        modelCapabilities: _parseModelCapabilities(
          rawCapabilities: json['modelCapabilities'],
          rawModels: json['models'],
        ),
      );

  static List<String> _normalizeModels(List<String>? input) {
    final source = input ?? const <String>[];
    final seen = <String>{};
    final result = <String>[];
    for (final item in source) {
      final model = item.trim();
      if (model.isEmpty || seen.contains(model)) continue;
      seen.add(model);
      result.add(model);
    }
    return result;
  }

  static Map<String, String> _normalizeRemarks({
    required Map<String, String>? remarks,
    required List<String> models,
  }) {
    final modelSet = models.toSet();
    final result = <String, String>{};
    if (remarks == null) return result;
    for (final entry in remarks.entries) {
      final key = entry.key.trim();
      final value = entry.value.trim();
      if (key.isEmpty || value.isEmpty) continue;
      if (!modelSet.contains(key)) continue;
      result[key] = value;
    }
    return result;
  }

  static Map<String, ModelFeatureOptions> _normalizeCapabilities({
    required Map<String, ModelFeatureOptions>? capabilities,
    required List<String> models,
  }) {
    final modelSet = models.toSet();
    final result = <String, ModelFeatureOptions>{};
    if (capabilities == null) return result;
    for (final entry in capabilities.entries) {
      final key = entry.key.trim();
      if (key.isEmpty || !modelSet.contains(key)) continue;
      final value = entry.value;
      // 即便视觉/工具都关闭，只要存在任一图像配置也要保留。
      if (!value.hasAnyCapability && !value.hasAnyImageConfig) continue;
      result[key] = value;
    }
    return result;
  }

  static List<String> _parseModels(dynamic rawModels) {
    if (rawModels is! List) return <String>[];
    final result = <String>[];
    for (final item in rawModels) {
      if (item is String) {
        result.add(item);
        continue;
      }
      if (item is Map) {
        final modelName =
            item['name']?.toString() ??
            item['model']?.toString() ??
            item['id']?.toString() ??
            '';
        if (modelName.isNotEmpty) {
          result.add(modelName);
        }
      }
    }
    return _normalizeModels(result);
  }

  static Map<String, String> _parseModelRemarks({
    required dynamic rawRemarks,
    required dynamic rawModels,
  }) {
    final models = _parseModels(rawModels);
    final remarks = <String, String>{};
    if (rawRemarks is Map) {
      for (final entry in rawRemarks.entries) {
        remarks[entry.key.toString()] = entry.value.toString();
      }
    }
    if (rawModels is List) {
      for (final item in rawModels) {
        if (item is! Map) continue;
        final modelName =
            item['name']?.toString() ??
            item['model']?.toString() ??
            item['id']?.toString() ??
            '';
        if (modelName.isEmpty) continue;
        final remark =
            item['remark']?.toString() ??
            item['displayName']?.toString() ??
            item['alias']?.toString() ??
            '';
        if (remark.trim().isEmpty) continue;
        remarks[modelName] = remark;
      }
    }
    return _normalizeRemarks(remarks: remarks, models: models);
  }

  static Map<String, ModelFeatureOptions> _parseModelCapabilities({
    required dynamic rawCapabilities,
    required dynamic rawModels,
  }) {
    final models = _parseModels(rawModels);
    final capabilities = <String, ModelFeatureOptions>{};

    if (rawCapabilities is Map) {
      for (final entry in rawCapabilities.entries) {
        capabilities[entry.key.toString()] = ModelFeatureOptions.fromDynamic(
          entry.value,
        );
      }
    }

    if (rawModels is List) {
      for (final item in rawModels) {
        if (item is! Map) continue;
        final modelName =
            item['name']?.toString() ??
            item['model']?.toString() ??
            item['id']?.toString() ??
            '';
        if (modelName.isEmpty) continue;
        capabilities[modelName] = ModelFeatureOptions.fromDynamic(item);
      }
    }

    return _normalizeCapabilities(capabilities: capabilities, models: models);
  }

  /// 根据已保存字段推断请求模式，兼容历史数据。
  static RequestMode inferRequestMode({
    required ProviderType type,
    String? baseUrl,
    String? urlPath,
    String? requestModeName,
  }) {
    if (requestModeName != null && requestModeName.isNotEmpty) {
      for (final mode in RequestMode.values) {
        if (mode.name == requestModeName) {
          return mode;
        }
      }
    }

    final normalizedBase = (baseUrl ?? '').toLowerCase();
    final normalizedPath = (urlPath ?? '').toLowerCase();
    if (type == ProviderType.gemini ||
        normalizedPath.contains(':generatecontent') ||
        normalizedPath.contains('/v1beta/models') ||
        normalizedBase.contains('generativelanguage.googleapis.com')) {
      return RequestMode.geminiGenerateContent;
    }

    if (type == ProviderType.claude ||
        normalizedPath.contains('/v1/messages') ||
        normalizedBase.contains('anthropic.com')) {
      return RequestMode.claudeMessages;
    }

    return RequestMode.openaiChat;
  }
}
