import '../models/ai_provider_config.dart';
import '../models/message.dart';

abstract class BaseAIProvider {
  final AIProviderConfig config;

  BaseAIProvider(this.config);

  /// 发送聊天消息，返回 AI 的回复
  Future<Message> sendChat({
    required List<Message> history,
    required String model,
    double temperature = 0.7,
    double topP = 1.0,
    int maxContext = 4096,
  });
}
