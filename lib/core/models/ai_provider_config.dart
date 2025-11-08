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
        return '/v1beta/modlels/[model]';
      case ProviderType.claude:
        return '/v1/messagess';
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

class AIProviderConfig {
  final String id;           // 唯一ID
  String name;         // 用户自定义名称
  ProviderType type;   // 提供方类型
  String? baseUrl;      // API基础URL
  String? urlPath;      //API路径
  String? apiKey;       // 用户提供的Key
  List<String> models;       // 模型列表

  AIProviderConfig({
    required this.id,
    required this.name,
    required this.type,
    this.baseUrl,
    this.urlPath,
    this.apiKey,
    List<String>? models,
  }) : models = models ?? []; 


  factory AIProviderConfig.newCustom() {
    return AIProviderConfig(
      id: const Uuid().v4(),
      name: '',
      type: ProviderType.openai,
      baseUrl: null,
      urlPath: null,
      apiKey: null,
      models: [],
    );
  }

  void updateConfig({
    String? name,
    ProviderType? type,
    String? baseUrl,
    String? apiKey,
    String? urlPath,
    List<String>? models,
  }){
    if (name != null && name.isNotEmpty) this.name = name;
    if (type != null) this.type = type;
    if (baseUrl != null) this.baseUrl = baseUrl;
    if (apiKey != null) this.apiKey = apiKey;
    if (urlPath != null) this.urlPath = urlPath;
    if (models != null) this.models = models;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'baseUrl': baseUrl,
    'urlPath': urlPath,
    'apiKey': apiKey,
    'models': models,
  };

  AIProviderConfig copyWith({
    String? id,
    String? name,
    ProviderType? type,
    String? baseUrl,
    String? urlPath,
    String? apiKey,
    List<String>? models,
  }) {
    return AIProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      baseUrl: baseUrl ?? this.baseUrl,
      urlPath: urlPath ?? this.urlPath,
      apiKey: apiKey ?? this.apiKey,
      models: models ?? this.models,
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
        baseUrl: json['baseUrl'],
        urlPath: json['urlPath'],
        apiKey: json['apiKey'],
        models: (json['models'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );
}
