import 'package:now_chat/core/models/ai_provider_config.dart';

class ProviderPreset {
  final String id;
  final String name;
  final String description;
  final ProviderType type;
  final RequestMode requestMode;
  final String baseUrl;
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

class ProviderCatalog {
  static const String customId = 'custom';

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

  static List<ProviderPreset> search(String keyword) {
    final query = keyword.trim().toLowerCase();
    if (query.isEmpty) return presets;
    return presets.where((preset) {
      return preset.name.toLowerCase().contains(query) ||
          preset.description.toLowerCase().contains(query);
    }).toList();
  }

  static ProviderPreset findById(String? id) {
    return presets.firstWhere(
      (preset) => preset.id == id,
      orElse: () => presets.first,
    );
  }

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
