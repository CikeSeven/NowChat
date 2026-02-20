import '../models/ai_provider_config.dart';
import '../models/message.dart';

/// AI 提供方抽象基类。
///
/// 该类用于封装“某一类模型协议”的最小调用能力，
/// 便于在不同 Provider 实现间复用统一接口。
abstract class BaseAIProvider {
  /// 提供方配置（baseUrl、apiKey、模型列表等）。
  final AIProviderConfig config;

  /// 构造函数，注入当前 Provider 的配置。
  BaseAIProvider(this.config);

  /// 发送聊天请求并返回一条 AI 消息。
  ///
  /// 参数：
  /// - [history] 当前会话历史消息（按时间升序）
  /// - [model] 目标模型名
  /// - [temperature]/[topP] 采样参数
  /// - [maxContext] 上下文长度上限
  Future<Message> sendChat({
    required List<Message> history,
    required String model,
    double temperature = 0.7,
    double topP = 1.0,
    int maxContext = 4096,
  });
}
