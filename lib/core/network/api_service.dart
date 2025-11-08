
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:isar/isar.dart';
import 'package:logger/web.dart';
import 'package:now_chat/core/models/message.dart';
import 'package:now_chat/util/app_logger.dart';
import '../models/ai_provider_config.dart';
import '../models/chat_session.dart';

class ApiService {


  // 流式对话
  static Future<void> sendChatRequestStreaming({
    required AIProviderConfig provider,
    required ChatSession session,
    required Isar isar,
    Function(String deltaContent, String? deltaReasoning)? onStream,
    Function()? onDone,
  }) async {
    final client = http.Client();
    final messages = await isar.messages
        .filter()
        .chatIdEqualTo(session.id)
        .sortByTimestamp()
        .findAll();
      
    // 过滤掉占位的空 assistant 消息
    final filteredMessages = messages.where((m) =>
        m.role != 'assistant' || (m.content.isNotEmpty && m.content.trim().isNotEmpty)
    ).toList();

    try {
      final base = provider.baseUrl!.replaceAll(RegExp(r"/$"), "");
      final path = provider.urlPath ?? '/v1/chat/completions';
      final uri = Uri.parse('$base$path');

      final headers = {
        'Authorization': 'Bearer ${provider.apiKey}',
        'Content-Type': 'application/json',
      };

      final body = {
        'model': session.model ?? provider.models.first,
        'messages': filteredMessages
            .map((m) => {
                  'role': m.role,
                  'content': m.content,
                })
            .toList(),
        'temperature': session.temperature,
        'top_p': session.topP,
        'max_tokens': session.maxTokens,
        'stream': true,
      };

      AppLogger.i("发起流式请求 → $uri");
      AppLogger.i("请求体：$body");

      final request = http.Request('POST', uri)
        ..headers.addAll(headers)
        ..body = jsonEncode(body);

      final response = await client.send(request);

      if (response.statusCode != 200) {
        final errorText = await response.stream.bytesToString();
        throw Exception('请求失败 (${response.statusCode}): $errorText');
      }

      final utf8Stream = response.stream.transform(utf8.decoder);
      String buffer = '';

      await for (final chunk in utf8Stream) {
        buffer += chunk;

        // SSE 通常用单 \n 分割，但部分服务可能用双 \n\n
        while (true) {
          final newlineIndex = buffer.indexOf('\n');
          if (newlineIndex == -1) break;

          var line = buffer.substring(0, newlineIndex).trim();
          buffer = buffer.substring(newlineIndex + 1);

          if (line.isEmpty) continue;

          if (line == '[DONE]' || line == 'data: [DONE]') {
            AppLogger.i('流式响应完成');
            onDone?.call();
            continue;
          }

          if (line.startsWith('data:')) {
            line = line.substring(5).trim();
          }

          // 尝试解析 JSON 格式的流数据
          try {
            final jsonData = jsonDecode(line);
            final choice = jsonData['choices']?[0]?['delta'];

            if (choice == null) continue;

            // reasoning_content 和 content 都有可能出现
            final reasoning = choice['reasoning_content'] ??
                choice['reasoning'] ??
                null;
            final content = choice['content'] ?? '';

            if ((content is String && content.isNotEmpty) ||
                (reasoning is String && reasoning.isNotEmpty)) {
              onStream?.call(content, reasoning);
            }
          } catch (e) {
            // 如果不是 JSON（有时可能返回文本或日志）
            AppLogger.w("无法解析 JSON 行：$line");
            onStream?.call(line, null);
          }
        }
      }

      AppLogger.i('流式请求结束');
    } catch (e, st) {
      AppLogger.e("流接收错误: $e\n$st");
      rethrow;
    } finally {
      client.close();
    }
  }



  // 非流式对话
  static Future<Map<String, dynamic>> sendChatRequest({
    required AIProviderConfig provider,
    required ChatSession session,
    required Isar isar,
  }) async {
    final Logger logger = Logger();

    final base = provider.baseUrl!.replaceAll(RegExp(r"/$"), "");
    final path = provider.urlPath ?? '/v1/chat/completions';
    final uri = Uri.parse('$base$path');
    logger.i("(非流式) 向 $base$path 发送对话请求");

    final messages = await isar.messages
        .filter()
        .chatIdEqualTo(session.id)
        .sortByTimestamp()
        .findAll();
      
    // 过滤掉占位的空 assistant 消息
    final filteredMessages = messages.where((m) =>
        m.role != 'assistant' || (m.content.isNotEmpty && m.content.trim().isNotEmpty)
    ).toList();

    final headers = {
      'Authorization': 'Bearer ${provider.apiKey}',
      'Content-Type': 'application/json',
    };

    final body = {
      'model': session.model ?? provider.models.first,
      'messages': filteredMessages
          .map((m) => {
                'role': m.role,
                'content': m.content,
              })
          .toList(),
      'temperature': session.temperature,
      'top_p': session.topP,
      'max_tokens': session.maxTokens,
    };

    logger.i("请求体为: $body");

    final response =
        await http.post(uri, headers: headers, body: jsonEncode(body));

    logger.i("返回体: ${response.body}");

    if (response.statusCode != 200) {
      throw Exception('请求失败: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body);
    logger.i("请求成功返回数据: $data");

    // --- 兼容多种响应格式 ---
    final content = data['choices']?[0]?['message']?['content'] ??
        data['output'] ??
        data['response'] ??
        data['message'] ??
        '（无返回内容）';

    return {
      'content': content,
      'reasoning': null,
      'reasoningTimeMs': null,
    };
  }

  // 获取模型列表
  static Future<List<String>> fetchModels(AIProviderConfig provider, String baseUrl, String apiKey) async {
    final Logger logger = Logger();

    String urlPath = "";
    switch (provider.type) {
      case ProviderType.openai:
      case ProviderType.deepseek:
      case ProviderType.openaiCompatible:
        if(provider.baseUrl!.contains('v1')) {
          urlPath = "$baseUrl/models";
        } else {
          urlPath = "$baseUrl/v1/models";
        }
        break;
      case ProviderType.gemini:
        urlPath = "$baseUrl/v1beta/models?key=$apiKey";
        break;
      default:
        urlPath = "$baseUrl/v1/models";
    }

    final url = Uri.parse(urlPath);

    logger.i("开始向url: $url 发送获取模型列表请求");
    final headers = {
      'Content-Type': 'application/json',
      if (provider.type != ProviderType.gemini)
        'Authorization': 'Bearer $apiKey',
    };
    final response = await http.get(url, headers: headers);
    logger.i("返回体：${response.body}");

    if (response.statusCode == 200) {
      try {
        final data = jsonDecode(response.body);
        if (data is Map && data['models'] is List) {
          return (data['models'] as List)
              .map((e) {
                final name = e['name']?.toString() ?? '';
                return name.startsWith('models/')
                    ? name.substring(7)
                    : name;
              })
              .where((id) => id.isNotEmpty)
              .toList();
        }

        else if (data is Map && data['data'] is List) {
          return (data['data'] as List)
              .map((e) => e['id']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toList();
        }

        else if (data is List) {
          return data.map((e) => e.toString()).toList();
        }

        throw Exception("未知的模型响应格式: ${data.runtimeType}");
      } catch (e, st) {
        logger.e("解析模型列表失败: $e\n$st");
        throw Exception("解析模型列表失败: $e");
      }
    } else {
      throw Exception("请求失败 (${response.statusCode}): ${response.body}");
    }
  }
}