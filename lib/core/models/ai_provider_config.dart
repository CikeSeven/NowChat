import 'package:uuid/uuid.dart';

enum ProviderType {
  openai,
  gemini,
  claude,
  ollama,
  deepseek,
  openaiCompatible; // OpenAI API兼容类型

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

  String get defaultBaseUrl {
    switch (this) {
      case ProviderType.openai:
        return 'https://api.openai.com';
      case ProviderType.gemini:
        return 'https://generativelanguage.googleapis.com';
      case ProviderType.claude:
        return 'https://api.anthropic.com';
      case ProviderType.ollama:
        return 'http://localhost:11434';
      case ProviderType.deepseek:
        return 'https://api.deepseek.com';
      case ProviderType.openaiCompatible:
        return '';
    }
  }

  String get defaultPath {
    switch (this) {
      case ProviderType.deepseek:
      case ProviderType.ollama:
      case ProviderType.openai:
        return '/v1/chat/completions';
      case ProviderType.gemini:
        return '/v1beta/models/[model]:generateContent';
      case ProviderType.claude:
        return '/v1/messages';
      case ProviderType.openaiCompatible:
        return '/chat/completions';
    }
  }

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

  bool get requiresApiKey {
    // 是否需要Key
    return true;
  }
}

enum RequestMode {
  openaiChat,
  geminiGenerateContent,
  claudeMessages;

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

  bool get supportsStreaming {
    switch (this) {
      case RequestMode.openaiChat:
      case RequestMode.geminiGenerateContent:
      case RequestMode.claudeMessages:
        return true;
    }
  }

  String get defaultPath {
    switch (this) {
      case RequestMode.openaiChat:
        return '/v1/chat/completions';
      case RequestMode.geminiGenerateContent:
        return '/v1beta/models/[model]:generateContent';
      case RequestMode.claudeMessages:
        return '/v1/messages';
    }
  }
}

class ModelFeatureOptions {
  final bool supportsVision;
  final bool supportsTools;

  const ModelFeatureOptions({
    this.supportsVision = false,
    this.supportsTools = false,
  });

  bool get hasAnyCapability => supportsVision || supportsTools;

  ModelFeatureOptions copyWith({bool? supportsVision, bool? supportsTools}) {
    return ModelFeatureOptions(
      supportsVision: supportsVision ?? this.supportsVision,
      supportsTools: supportsTools ?? this.supportsTools,
    );
  }

  Map<String, dynamic> toJson() => {
    'supportsVision': supportsVision,
    'supportsTools': supportsTools,
  };

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
      return ModelFeatureOptions(
        supportsVision: supportsVision,
        supportsTools: supportsTools,
      );
    }
    return const ModelFeatureOptions();
  }
}

class AIProviderConfig {
  final String id; // 唯一ID
  String name; // 用户自定义名称
  ProviderType type; // 提供方类型
  RequestMode requestMode; // 请求方式
  String? baseUrl; // API基础URL
  String? urlPath; //API路径
  String? apiKey; // 用户提供的Key
  List<String> models; // 模型列表
  Map<String, String> modelRemarks; // 模型备注（key: 模型名, value: 备注名）
  Map<String, ModelFeatureOptions> modelCapabilities; // 模型能力配置

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

  String displayNameForModel(String model) {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return model;
    final remark = modelRemarks[trimmed]?.trim();
    if (remark == null || remark.isEmpty) return trimmed;
    return remark;
  }

  ModelFeatureOptions featuresForModel(String model) {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return const ModelFeatureOptions();
    return modelCapabilities[trimmed] ?? const ModelFeatureOptions();
  }

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
      if (!value.hasAnyCapability) continue;
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
