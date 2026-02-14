import 'package:now_chat/core/models/ai_provider_config.dart';

/// 提供方预设配置。
class ProviderPreset {
  /// 预设唯一标识。
  final String id;

  /// 预设显示名称。
  final String name;

  /// 预设描述信息。
  final String description;

  /// 提供方类型。
  final ProviderType type;

  /// 请求协议模式。
  final RequestMode requestMode;

  /// 默认基础地址。
  final String baseUrl;

  /// 默认请求路径。
  final String path;

  const ProviderPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    this.requestMode = RequestMode.openaiChat,
    required this.baseUrl,
    required this.path,
  });
}

/// 内置提供方目录与检索逻辑。
class ProviderCatalog {
  /// “自定义”预设 ID。
  static const String customId = 'custom';

  /// 应用内可选预设列表。
  static const List<ProviderPreset> presets = [
    ProviderPreset(
      id: 'openai',
      name: 'OpenAI',
      description: '官方 OpenAI 接口',
      type: ProviderType.openai,
      baseUrl: 'https://api.openai.com',
      path: '/v1/chat/completions',
    ),
    ProviderPreset(
      id: 'gemini',
      name: 'Gemini',
      description: 'Google Gemini 接口',
      type: ProviderType.gemini,
      requestMode: RequestMode.geminiGenerateContent,
      baseUrl: 'https://generativelanguage.googleapis.com',
      path: '/v1beta/models/[model]:generateContent',
    ),
    ProviderPreset(
      id: 'claude',
      name: 'Claude',
      description: 'Anthropic Claude 接口',
      type: ProviderType.claude,
      requestMode: RequestMode.claudeMessages,
      baseUrl: 'https://api.anthropic.com',
      path: '/v1/messages',
    ),
    ProviderPreset(
      id: 'deepseek',
      name: 'DeepSeek',
      description: 'DeepSeek 官方接口',
      type: ProviderType.deepseek,
      baseUrl: 'https://api.deepseek.com',
      path: '/v1/chat/completions',
    ),
    ProviderPreset(
      id: 'zhipu',
      name: '智谱 AI (GLM)',
      description: '智谱大模型，默认使用 GLM OpenAI 兼容地址',
      type: ProviderType.openaiCompatible,
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      path: '/chat/completions',
    ),
    ProviderPreset(
      id: 'qwen',
      name: '通义千问 (Qwen)',
      description: '阿里云百炼兼容模式',
      type: ProviderType.openaiCompatible,
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode',
      path: '/v1/chat/completions',
    ),
    ProviderPreset(
      id: 'doubao',
      name: '豆包 (Volcengine Ark)',
      description: '火山引擎 Ark API',
      type: ProviderType.openaiCompatible,
      baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
      path: '/chat/completions',
    ),
    ProviderPreset(
      id: 'hunyuan',
      name: '腾讯混元',
      description: '腾讯混元 OpenAI 兼容地址',
      type: ProviderType.openaiCompatible,
      baseUrl: 'https://api.hunyuan.cloud.tencent.com/v1',
      path: '/chat/completions',
    ),
    ProviderPreset(
      id: 'qianfan',
      name: '百度千帆',
      description: '百度千帆推理 API',
      type: ProviderType.openaiCompatible,
      baseUrl: 'https://qianfan.baidubce.com/v2',
      path: '/chat/completions',
    ),
    ProviderPreset(
      id: 'ollama',
      name: 'Ollama',
      description: '本地模型服务',
      type: ProviderType.ollama,
      baseUrl: 'http://localhost:11434',
      path: '/v1/chat/completions',
    ),
    ProviderPreset(
      id: 'openrouter',
      name: 'OpenRouter',
      description: '多模型聚合平台',
      type: ProviderType.openaiCompatible,
      baseUrl: 'https://openrouter.ai/api',
      path: '/v1/chat/completions',
    ),
    ProviderPreset(
      id: 'moonshot',
      name: 'Moonshot (Kimi)',
      description: '月之暗面 Kimi API',
      type: ProviderType.openaiCompatible,
      baseUrl: 'https://api.moonshot.cn',
      path: '/v1/chat/completions',
    ),
    ProviderPreset(
      id: 'lingyi',
      name: '零一万物 (Yi)',
      description: 'Yi 系列模型 API',
      type: ProviderType.openaiCompatible,
      baseUrl: 'https://api.lingyiwanwu.com',
      path: '/v1/chat/completions',
    ),
    ProviderPreset(
      id: 'stepfun',
      name: '阶跃星辰 (StepFun)',
      description: 'StepFun API',
      type: ProviderType.openaiCompatible,
      baseUrl: 'https://api.stepfun.com',
      path: '/v1/chat/completions',
    ),
    ProviderPreset(
      id: 'siliconflow',
      name: '硅基流动 (SiliconFlow)',
      description: 'SiliconFlow 模型平台',
      type: ProviderType.openaiCompatible,
      baseUrl: 'https://api.siliconflow.cn',
      path: '/v1/chat/completions',
    ),
    ProviderPreset(
      id: 'azure_openai',
      name: 'Azure OpenAI',
      description: 'Azure OpenAI 兼容模式',
      type: ProviderType.openaiCompatible,
      baseUrl: 'https://{resource}.openai.azure.com',
      path:
          '/openai/deployments/{deployment}/chat/completions?api-version=2024-02-15-preview',
    ),
    ProviderPreset(
      id: customId,
      name: '自定义',
      description: '手动填写兼容 OpenAI 的接口',
      type: ProviderType.openaiCompatible,
      baseUrl: '',
      path: '/v1/chat/completions',
    ),
  ];

  /// 按名称或描述搜索预设。
  static List<ProviderPreset> search(String keyword) {
    final query = keyword.trim().toLowerCase();
    if (query.isEmpty) return presets;
    return presets.where((preset) {
      return preset.name.toLowerCase().contains(query) ||
          preset.description.toLowerCase().contains(query);
    }).toList();
  }

  /// 根据 ID 获取预设，找不到时回退首项。
  static ProviderPreset findById(String? id) {
    return presets.firstWhere(
      (preset) => preset.id == id,
      orElse: () => presets.first,
    );
  }

  /// 从用户配置反查最匹配的预设。
  static ProviderPreset matchFromConfig(AIProviderConfig config) {
    final currentBaseUrl = (config.baseUrl ?? '').trim().toLowerCase();
    final currentPath = (config.urlPath ?? '').trim().toLowerCase();

    for (final preset in presets) {
      final isSameType = preset.type == config.type;
      final isSameRequestMode = preset.requestMode == config.requestMode;
      final isSameBase = preset.baseUrl.trim().toLowerCase() == currentBaseUrl;
      final isSamePath = preset.path.trim().toLowerCase() == currentPath;
      if (isSameType && isSameRequestMode && isSameBase && isSamePath) {
        return preset;
      }
    }
    return findById(customId);
  }
}
