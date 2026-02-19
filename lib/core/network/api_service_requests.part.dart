part of 'api_service.dart';

/// API 非流式请求与模型列表拉取实现。

/// 内部非流式请求入口，根据请求模式路由协议实现。
Future<Map<String, dynamic>> _sendChatRequestInternal({
  required AIProviderConfig provider,
  required ChatSession session,
  required Isar isar,
  GenerationAbortController? abortController,
  List<Message>? overrideMessages,
  FutureOr<void> Function(Map<String, dynamic> toolLog)? onToolLog,
}) async {
  switch (provider.requestMode) {
    case RequestMode.openaiChat:
      return _sendOpenAIChatRequest(
        provider: provider,
        session: session,
        isar: isar,
        abortController: abortController,
        overrideMessages: overrideMessages,
        onToolLog: onToolLog,
      );
    case RequestMode.geminiGenerateContent:
      return _sendGeminiRequest(
        provider: provider,
        session: session,
        isar: isar,
        abortController: abortController,
        overrideMessages: overrideMessages,
      );
    case RequestMode.claudeMessages:
      return _sendClaudeRequest(
        provider: provider,
        session: session,
        isar: isar,
        abortController: abortController,
        overrideMessages: overrideMessages,
      );
  }
}

/// 发送 OpenAI/OpenAI 兼容协议的非流式请求。
Future<Map<String, dynamic>> _sendOpenAIChatRequest({
  required AIProviderConfig provider,
  required ChatSession session,
  required Isar isar,
  GenerationAbortController? abortController,
  List<Message>? overrideMessages,
  FutureOr<void> Function(Map<String, dynamic> toolLog)? onToolLog,
}) async {
  final logger = Logger();
  final base = _normalizeBaseUrl(provider.baseUrl);
  final path = _resolvePath(provider);
  final uri = _buildUri(base, path);
  final model = _resolveModel(provider, session);
  final filteredMessages = await _resolveRequestMessages(
    isar,
    session,
    overrideMessages: overrideMessages,
  );
  final allowVision = _supportsVisionForSessionModel(provider, session);
  final systemPrompt = _resolvedSystemPrompt(session);

  final headers = <String, String>{'Content-Type': 'application/json'};
  final apiKey = (provider.apiKey ?? '').trim();
  if (apiKey.isNotEmpty) {
    headers['Authorization'] = 'Bearer $apiKey';
  }
  final shouldUseTools = _isToolCallingEnabledForSession(provider, session);
  var remainingToolCalls = session.maxToolCalls <= 0 ? 0 : session.maxToolCalls;
  final toolLogs = <Map<String, dynamic>>[];
  // 会话级消息上下文，后续会在工具调用循环中持续追加 assistant/tool 消息。
  final conversation = await _buildOpenAIMessagesPayload(
    filteredMessages,
    allowVision: allowVision,
    systemPrompt: systemPrompt,
  );
  final responseTextBuffer = StringBuffer();

  logger.i("(OpenAI) 向 $uri 发送对话请求");
  final client = http.Client();
  abortController?.onAbort(client.close);
  try {
    // 非流式也采用“请求 -> 工具调用 -> 再请求”的多轮闭环，直到模型不再请求工具。
    while (true) {
      if (_isAbortTriggered(abortController)) {
        throw const GenerationAbortedException();
      }
      final body = <String, dynamic>{
        'model': model,
        'messages': conversation,
        'temperature': session.temperature,
        'top_p': session.topP,
        if (session.maxTokens > 0) 'max_tokens': session.maxTokens,
        if (shouldUseTools && remainingToolCalls > 0)
          'tools': AIToolRuntime.buildOpenAIToolsSchema(),
        if (shouldUseTools && remainingToolCalls > 0) 'tool_choice': 'auto',
      };

      final response = await client.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      );
      logger.i("返回体: ${response.body}");

      if (response.statusCode != 200) {
        throw Exception('请求失败: ${response.statusCode} ${response.body}');
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) {
        throw const FormatException('OpenAI 响应格式错误');
      }

      dynamic message;
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final firstChoice = choices.first;
        if (firstChoice is Map) {
          message = firstChoice['message'];
        }
      }

      final content = _extractOpenAIMessageContentText(
        message is Map ? Map<String, dynamic>.from(message) : null,
      );
      if (content.isNotEmpty) {
        responseTextBuffer.write(content);
      }
      final toolCalls = _parseOpenAIToolCallsFromMessage(message);
      if (toolCalls.isEmpty || !shouldUseTools) {
        // 无工具调用时，说明已得到最终文本结果。
        break;
      }
      if (remainingToolCalls <= 0) {
        final skippedLog = <String, dynamic>{
          'callId': 'limit_reached',
          'toolName': 'tool_limit',
          'status': 'skipped',
          'summary': '工具调用达到上限(${session.maxToolCalls})，停止继续调用',
        };
        toolLogs.add(skippedLog);
        await onToolLog?.call(skippedLog);
        break;
      }

      conversation.add(<String, dynamic>{
        'role': 'assistant',
        if (content.isNotEmpty) 'content': content,
        'tool_calls':
            toolCalls
                .map((call) => _toOpenAIToolCallPayload(call))
                .toList(growable: false),
      });

      for (final call in toolCalls) {
        if (remainingToolCalls <= 0) break;
        // 串行执行工具，保证模型看到的 tool 响应顺序稳定。
        final result = await AIToolRuntime.execute(call);
        remainingToolCalls -= 1;

        final log = <String, dynamic>{
          'callId': call.id,
          'toolName': call.name,
          'status': result.status,
          'summary': result.summary,
          if (result.error != null) 'error': result.error,
          if (result.durationMs != null) 'durationMs': result.durationMs,
        };
        toolLogs.add(log);
        await onToolLog?.call(log);

        conversation.add(<String, dynamic>{
          'role': 'tool',
          'tool_call_id': call.id,
          'content': result.toolMessageContent,
        });
      }
    }

    final content = responseTextBuffer.toString();
    return {
      'content': content.isEmpty ? '（无返回内容）' : content,
      'reasoning': null,
      'reasoningTimeMs': null,
      'toolLogs': toolLogs,
    };
  } on GenerationAbortedException {
    logger.i("(OpenAI) 请求已中断");
    rethrow;
  } catch (e) {
    if (_isAbortTriggered(abortController)) {
      logger.i("(OpenAI) 请求在中断后关闭连接");
      throw const GenerationAbortedException();
    }
    rethrow;
  } finally {
    client.close();
  }
}

/// 发送 Gemini GenerateContent 非流式请求。
Future<Map<String, dynamic>> _sendGeminiRequest({
  required AIProviderConfig provider,
  required ChatSession session,
  required Isar isar,
  GenerationAbortController? abortController,
  List<Message>? overrideMessages,
}) async {
  final logger = Logger();
  final base = _normalizeBaseUrl(provider.baseUrl);
  final model = _resolveModel(provider, session);
  final rawPath = _resolvePath(provider);
  final resolvedPath =
      rawPath.contains('[model]')
          ? rawPath.replaceAll('[model]', model)
          : rawPath;
  final apiKey = (provider.apiKey ?? '').trim();
  final uri = _buildUri(
    base,
    resolvedPath,
    queryParameters: apiKey.isEmpty ? null : {'key': apiKey},
  );

  final filteredMessages = await _resolveRequestMessages(
    isar,
    session,
    overrideMessages: overrideMessages,
  );
  final allowVision = _supportsVisionForSessionModel(provider, session);
  final systemPrompt = _resolvedSystemPrompt(session);
  final geminiSystemInstruction = _buildGeminiSystemInstruction(systemPrompt);
  final contents = await _buildGeminiContentsPayload(
    filteredMessages,
    allowVision: allowVision,
  );

  final body = {
    'contents': contents,
    if (geminiSystemInstruction != null)
      'systemInstruction': geminiSystemInstruction,
    'generationConfig': {
      'temperature': session.temperature,
      'topP': session.topP,
      if (session.maxTokens > 0) 'maxOutputTokens': session.maxTokens,
    },
  };

  logger.i("(Gemini) 向 $uri 发送对话请求");
  final client = http.Client();
  abortController?.onAbort(client.close);
  try {
    if (_isAbortTriggered(abortController)) {
      throw const GenerationAbortedException();
    }
    final response = await client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    logger.i("返回体: ${response.body}");

    if (response.statusCode != 200) {
      throw Exception('请求失败: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body);
    final candidates = data['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw Exception('Gemini 响应缺少 candidates');
    }
    final parts = candidates[0]?['content']?['parts'];
    if (parts is! List || parts.isEmpty) {
      throw Exception('Gemini 响应缺少内容');
    }
    final content = parts
        .map((part) => part['text']?.toString() ?? '')
        .where((text) => text.isNotEmpty)
        .join('\n');

    return {'content': content, 'reasoning': null, 'reasoningTimeMs': null};
  } on GenerationAbortedException {
    logger.i("(Gemini) 请求已中断");
    rethrow;
  } catch (e) {
    if (_isAbortTriggered(abortController)) {
      logger.i("(Gemini) 请求在中断后关闭连接");
      throw const GenerationAbortedException();
    }
    rethrow;
  } finally {
    client.close();
  }
}

/// 发送 Claude Messages 非流式请求。
Future<Map<String, dynamic>> _sendClaudeRequest({
  required AIProviderConfig provider,
  required ChatSession session,
  required Isar isar,
  GenerationAbortController? abortController,
  List<Message>? overrideMessages,
}) async {
  final logger = Logger();
  final base = _normalizeBaseUrl(provider.baseUrl);
  final path = _resolvePath(provider);
  final uri = _buildUri(base, path);
  final model = _resolveModel(provider, session);
  final apiKey = (provider.apiKey ?? '').trim();

  final filteredMessages = await _resolveRequestMessages(
    isar,
    session,
    overrideMessages: overrideMessages,
  );
  final allowVision = _supportsVisionForSessionModel(provider, session);
  final systemPrompt = _resolvedSystemPrompt(session);
  final messages = await _buildClaudeMessagesPayload(
    filteredMessages,
    allowVision: allowVision,
  );

  final body = {
    'model': model,
    if (session.maxTokens > 0) 'max_tokens': session.maxTokens,
    'temperature': session.temperature,
    'top_p': session.topP,
    'messages': messages,
    if (systemPrompt != null) 'system': systemPrompt,
  };

  logger.i("(Claude) 向 $uri 发送对话请求");
  final client = http.Client();
  abortController?.onAbort(client.close);
  try {
    if (_isAbortTriggered(abortController)) {
      throw const GenerationAbortedException();
    }
    final response = await client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode(body),
    );
    logger.i("返回体: ${response.body}");

    if (response.statusCode != 200) {
      throw Exception('请求失败: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body);
    final contentList = data['content'];
    if (contentList is! List || contentList.isEmpty) {
      throw Exception('Claude 响应缺少 content');
    }
    final content = contentList
        .map((item) => item['text']?.toString() ?? '')
        .where((text) => text.isNotEmpty)
        .join('\n');

    return {'content': content, 'reasoning': null, 'reasoningTimeMs': null};
  } on GenerationAbortedException {
    logger.i("(Claude) 请求已中断");
    rethrow;
  } catch (e) {
    if (_isAbortTriggered(abortController)) {
      logger.i("(Claude) 请求在中断后关闭连接");
      throw const GenerationAbortedException();
    }
    rethrow;
  } finally {
    client.close();
  }
}

/// 内部模型列表拉取入口。
Future<List<String>> _fetchModelsInternal(
  AIProviderConfig provider,
  String baseUrl,
  String apiKey,
) async {
  final logger = Logger();

  late final String urlPath;
  switch (provider.type) {
    case ProviderType.openai:
    case ProviderType.deepseek:
    case ProviderType.openaiCompatible:
      urlPath = _buildOpenAIStyleModelsEndpoint(baseUrl);
      break;
    case ProviderType.gemini:
      urlPath = '$baseUrl/v1beta/models?key=$apiKey';
      break;
    default:
      urlPath = '$baseUrl/v1/models';
  }

  final url = Uri.parse(urlPath);
  logger.i("开始向url: $url 发送获取模型列表请求");

  final headers = {
    'Content-Type': 'application/json',
    if (provider.type != ProviderType.gemini) 'Authorization': 'Bearer $apiKey',
  };

  final http.Response response;
  try {
    response = await http
        .get(url, headers: headers)
        .timeout(_fetchModelsTimeout);
  } on TimeoutException {
    throw Exception('获取模型列表超时（${_fetchModelsTimeout.inSeconds} 秒），请检查网络或接口地址');
  }
  logger.i("返回体：${response.body}");

  if (response.statusCode != 200) {
    throw Exception("请求失败 (${response.statusCode}): ${response.body}");
  }

  try {
    final data = jsonDecode(response.body);
    if (data is Map && data['models'] is List) {
      return (data['models'] as List)
          .map((e) {
            final name = e['name']?.toString() ?? '';
            return name.startsWith('models/') ? name.substring(7) : name;
          })
          .where((id) => id.isNotEmpty)
          .toList();
    } else if (data is Map && data['data'] is List) {
      return (data['data'] as List)
          .map((e) => e['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    } else if (data is List) {
      return data.map((e) => e.toString()).toList();
    }
    throw Exception("未知的模型响应格式: ${data.runtimeType}");
  } catch (e, st) {
    logger.e("解析模型列表失败: $e\n$st");
    throw Exception("解析模型列表失败: $e");
  }
}
