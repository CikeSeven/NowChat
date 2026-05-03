import 'package:now_chat/core/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Message JSON round trip preserves performance-relevant fields', () {
    // 纯模型测试不依赖 Isar native core，保证 CI/离线环境也能稳定验证数据结构。
    final timestamp = DateTime.utc(2026, 5, 3, 12, 30);
    final message = Message(
      chatId: 42,
      role: 'assistant',
      content: 'hello',
      reasoning: 'thinking',
      reasoningTimeMs: 1200,
      imagePaths: const <String>['/storage/test.png'],
      timestamp: timestamp,
    );

    final restored = Message.fromJson(message.toJson());

    expect(restored.chatId, 42);
    expect(restored.role, 'assistant');
    expect(restored.content, 'hello');
    expect(restored.reasoning, 'thinking');
    expect(restored.reasoningTimeMs, 1200);
    expect(restored.imagePaths, const <String>['/storage/test.png']);
    expect(restored.timestamp, timestamp);
  });
}
