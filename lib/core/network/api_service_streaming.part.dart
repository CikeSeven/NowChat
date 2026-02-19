part of 'api_service.dart';

/// API 流式请求实现（OpenAI / Gemini / Claude）。

/// 内部流式请求入口，根据请求模式路由到具体协议实现。
Future<void> _sendChatRequestStreamingInternal({
  required AIProviderConfig provider,
  required ChatSession session,
  required Isar isar,
  GenerationAbortController? abortController,
  List<Message>? overrideMessages,
  FutureOr<void> Function(String deltaContent, String? deltaReasoning)?
  onStream,
  FutureOr<void> Function(Map<String, dynamic> toolLog)? onToolLog,
  FutureOr<void> Function()? onDone,
}) async {
  switch (provider.requestMode) {
    case RequestMode.openaiChat:
      await _sendOpenAIChatStreaming(
        provider: provider,
        session: session,
        isar: isar,
        abortController: abortController,
        overrideMessages: overrideMessages,
        onStream: onStream,
        onToolLog: onToolLog,
        onDone: onDone,
      );
      return;
    case RequestMode.geminiGenerateContent:
      await _sendGeminiRequestStreaming(
        provider: provider,
        session: session,
        isar: isar,
        abortController: abortController,
        overrideMessages: overrideMessages,
        onStream: onStream,
        onDone: onDone,
      );
      return;
    case RequestMode.claudeMessages:
      await _sendClaudeRequestStreaming(
        provider: provider,
        session: session,
        isar: isar,
        abortController: abortController,
        overrideMessages: overrideMessages,
        onStream: onStream,
        onDone: onDone,
      );
      return;
  }
}

/// 发送 OpenAI/OpenAI 兼容协议的流式请求。
Future<void> _sendOpenAIChatStreaming({
  required AIProviderConfig provider,
  required ChatSession session,
  required Isar isar,
  GenerationAbortController? abortController,
  List<Message>? overrideMessages,
  FutureOr<void> Function(String deltaContent, String? deltaReasoning)?
  onStream,
  FutureOr<void> Function(Map<String, dynamic> toolLog)? onToolLog,
  FutureOr<void> Function()? onDone,
}) async {
  final client = http.Client();
  abortController?.onAbort(client.close);

  final filteredMessages = await _resolveRequestMessages(
    isar,
    session,
    overrideMessages: overrideMessages,
  );

  try {
    if (_isAbortTriggered(abortController)) {
      throw const GenerationAbortedException();
    }

    final base = _normalizeBaseUrl(provider.baseUrl);
    final path = _resolvePath(provider);
    final uri = _buildUri(base, path);
    final model = _resolveModel(provider, session);
    final allowVision = _supportsVisionForSessionModel(provider, session);
    final systemPrompt = _resolvedSystemPrompt(session);
    final shouldUseTools = _isToolCallingEnabledForSession(provider, session);
    var remainingToolCalls = session.maxToolCalls <= 0 ? 0 : session.maxToolCalls;

    final headers = <String, String>{'Content-Type': 'application/json'};
    final apiKey = (provider.apiKey ?? '').trim();
    if (apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    final conversation = await _buildOpenAIMessagesPayload(
      filteredMessages,
      allowVision: allowVision,
      systemPrompt: systemPrompt,
    );

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
        'stream': true,
        if (shouldUseTools && remainingToolCalls > 0)
          'tools': AIToolRuntime.buildOpenAIToolsSchema(),
        if (shouldUseTools && remainingToolCalls > 0) 'tool_choice': 'auto',
      };

      AppLogger.i("(OpenAI) 发起流式请求 -> $uri");
      final request =
          http.Request('POST', uri)
            ..headers.addAll(headers)
            ..body = jsonEncode(body);

      final response = await client.send(request);
      if (response.statusCode != 200) {
        final errorText = await response.stream.bytesToString();
        throw Exception('请求失败 (${response.statusCode}): $errorText');
      }

      final utf8Stream = response.stream.transform(utf8.decoder);
      var buffer = '';
      final assistantContentBuffer = StringBuffer();
      final toolCallBuilders = <int, _StreamingToolCallBuilder>{};

      await for (final chunk in utf8Stream) {
        if (_isAbortTriggered(abortController)) {
          throw const GenerationAbortedException();
        }
        buffer += chunk;
        while (true) {
          if (_isAbortTriggered(abortController)) {
            throw const GenerationAbortedException();
          }
          final newlineIndex = buffer.indexOf('\n');
          if (newlineIndex == -1) break;

          var line = buffer.substring(0, newlineIndex).trim();
          buffer = buffer.substring(newlineIndex + 1);
          if (line.isEmpty) continue;
          if (line == '[DONE]' || line == 'data: [DONE]') continue;

          if (line.startsWith('data:')) {
            line = line.substring(5).trim();
          }

          try {
            final jsonData = jsonDecode(line);
            if (jsonData is! Map<String, dynamic>) continue;

            final choices = jsonData['choices'];
            if (choices is! List || choices.isEmpty) continue;
            final firstChoice = choices.first;
            if (firstChoice is! Map) continue;
            final delta = firstChoice['delta'];
            if (delta is! Map) continue;

            final reasoningRaw = delta['reasoning_content'] ?? delta['reasoning'];
            final contentRaw = delta['content'];
            final reasoning = reasoningRaw is String ? reasoningRaw : null;
            final content = contentRaw is String ? contentRaw : '';
            if (content.isNotEmpty || (reasoning?.isNotEmpty ?? false)) {
              await onStream?.call(content, reasoning);
            }
            if (content.isNotEmpty) {
              assistantContentBuffer.write(content);
            }

            final toolCallsRaw = delta['tool_calls'];
            if (toolCallsRaw is List) {
              _mergeOpenAIStreamingToolCalls(toolCallsRaw, toolCallBuilders);
            }
          } catch (_) {
            AppLogger.w("无法解析 JSON 行：$line");
          }
        }
      }

      final toolCalls = _finalizeOpenAIStreamingToolCalls(toolCallBuilders);
      if (toolCalls.isEmpty || !shouldUseTools) {
        break;
      }

      if (remainingToolCalls <= 0) {
        final skippedLog = <String, dynamic>{
          'callId': 'limit_reached',
          'toolName': 'tool_limit',
          'status': 'skipped',
          'summary': '工具调用达到上限(${session.maxToolCalls})，停止继续调用',
        };
        await onToolLog?.call(skippedLog);
        break;
      }

      final assistantContent = assistantContentBuffer.toString();
      conversation.add(<String, dynamic>{
        'role': 'assistant',
        if (assistantContent.isNotEmpty) 'content': assistantContent,
        'tool_calls':
            toolCalls
                .map((call) => _toOpenAIToolCallPayload(call))
                .toList(growable: false),
      });

      for (final call in toolCalls) {
        if (remainingToolCalls <= 0) break;
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
        await onToolLog?.call(log);

        conversation.add(<String, dynamic>{
          'role': 'tool',
          'tool_call_id': call.id,
          'content': result.toolMessageContent,
        });
      }
    }

    await onDone?.call();
  } on GenerationAbortedException {
    AppLogger.i("(OpenAI) 流式请求已中断");
    rethrow;
  } catch (e, st) {
    if (_isAbortTriggered(abortController)) {
      AppLogger.i("(OpenAI) 流式请求在中断后关闭连接");
      throw const GenerationAbortedException();
    }
    AppLogger.e("流接收错误: $e\n$st");
    rethrow;
  } finally {
    client.close();
  }
}

/// 发送 Gemini 流式请求（SSE）。
Future<void> _sendGeminiRequestStreaming({
  required AIProviderConfig provider,
  required ChatSession session,
  required Isar isar,
  GenerationAbortController? abortController,
  List<Message>? overrideMessages,
  FutureOr<void> Function(String deltaContent, String? deltaReasoning)?
  onStream,
  FutureOr<void> Function()? onDone,
}) async {
  final client = http.Client();
  abortController?.onAbort(client.close);
  var doneEmitted = false;
  String? lastSnapshot;

  try {
    if (_isAbortTriggered(abortController)) {
      throw const GenerationAbortedException();
    }

    final base = _normalizeBaseUrl(provider.baseUrl);
    final model = _resolveModel(provider, session);
    final rawPath = _resolvePath(provider);
    final resolvedPath =
        rawPath.contains('[model]')
            ? rawPath.replaceAll('[model]', model)
            : rawPath;
    final streamPath = _buildGeminiStreamingPath(resolvedPath);
    final apiKey = (provider.apiKey ?? '').trim();
    final queryParameters = <String, String>{'alt': 'sse'};
    if (apiKey.isNotEmpty) {
      queryParameters['key'] = apiKey;
    }
    final uri = _buildUri(base, streamPath, queryParameters: queryParameters);

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

    AppLogger.i("(Gemini) 发起流式请求 -> $uri");
    final request =
        http.Request('POST', uri)
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode(body);

    final response = await client.send(request);
    if (response.statusCode != 200) {
      final errorText = await response.stream.bytesToString();
      throw Exception('请求失败 (${response.statusCode}): $errorText');
    }

    final utf8Stream = response.stream.transform(utf8.decoder);
    await _consumeSseEvents(
      source: utf8Stream,
      onEvent: (event, data) async {
        if (_isAbortTriggered(abortController)) {
          throw const GenerationAbortedException();
        }
        final payloadText = data.trim();
        if (payloadText.isEmpty) return;

        if (payloadText == '[DONE]') {
          if (!doneEmitted) {
            doneEmitted = true;
            await onDone?.call();
          }
          return;
        }

        try {
          final decoded = jsonDecode(payloadText);
          if (decoded is! Map<String, dynamic>) return;

          final chunkText = _extractGeminiTextFromChunk(decoded);
          if (chunkText.isEmpty) return;

          var delta = chunkText;
          if (lastSnapshot != null) {
            if (chunkText.startsWith(lastSnapshot!)) {
              delta = chunkText.substring(lastSnapshot!.length);
              lastSnapshot = chunkText;
            } else if (lastSnapshot!.startsWith(chunkText)) {
              delta = '';
            } else {
              lastSnapshot = '${lastSnapshot!}$chunkText';
            }
          } else {
            lastSnapshot = chunkText;
          }

          if (delta.isNotEmpty) {
            await onStream?.call(delta, null);
          }
        } catch (_) {
          AppLogger.w("(Gemini) 无法解析流式事件: event=$event, data=$data");
        }
      },
    );

    if (!doneEmitted) {
      doneEmitted = true;
      await onDone?.call();
    }
  } on GenerationAbortedException {
    AppLogger.i("(Gemini) 流式请求已中断");
    rethrow;
  } catch (e, st) {
    if (_isAbortTriggered(abortController)) {
      AppLogger.i("(Gemini) 流式请求在中断后关闭连接");
      throw const GenerationAbortedException();
    }
    AppLogger.e("(Gemini) 流接收错误: $e\n$st");
    rethrow;
  } finally {
    client.close();
  }
}

/// 发送 Claude 流式请求（SSE）。
Future<void> _sendClaudeRequestStreaming({
  required AIProviderConfig provider,
  required ChatSession session,
  required Isar isar,
  GenerationAbortController? abortController,
  List<Message>? overrideMessages,
  FutureOr<void> Function(String deltaContent, String? deltaReasoning)?
  onStream,
  FutureOr<void> Function()? onDone,
}) async {
  final client = http.Client();
  abortController?.onAbort(client.close);
  var doneEmitted = false;

  try {
    if (_isAbortTriggered(abortController)) {
      throw const GenerationAbortedException();
    }

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
      'stream': true,
    };

    AppLogger.i("(Claude) 发起流式请求 -> $uri");
    final request =
        http.Request('POST', uri)
          ..headers.addAll({
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
          })
          ..body = jsonEncode(body);

    final response = await client.send(request);
    if (response.statusCode != 200) {
      final errorText = await response.stream.bytesToString();
      throw Exception('请求失败 (${response.statusCode}): $errorText');
    }

    final utf8Stream = response.stream.transform(utf8.decoder);
    await _consumeSseEvents(
      source: utf8Stream,
      onEvent: (event, data) async {
        if (_isAbortTriggered(abortController)) {
          throw const GenerationAbortedException();
        }
        final payloadText = data.trim();
        if (payloadText.isEmpty) return;

        if (payloadText == '[DONE]') {
          if (!doneEmitted) {
            doneEmitted = true;
            await onDone?.call();
          }
          return;
        }

        try {
          final decoded = jsonDecode(payloadText);
          if (decoded is! Map<String, dynamic>) return;

          final eventType =
              event.isNotEmpty ? event : (decoded['type']?.toString() ?? '');

          if (eventType == 'content_block_start') {
            final contentBlock = decoded['content_block'];
            if (contentBlock is Map) {
              final initialText = contentBlock['text']?.toString() ?? '';
              if (initialText.isNotEmpty) {
                await onStream?.call(initialText, null);
              }
            }
            return;
          }

          if (eventType == 'content_block_delta') {
            final delta = decoded['delta'];
            if (delta is Map) {
              final text = delta['text']?.toString() ?? '';
              if (text.isNotEmpty) {
                await onStream?.call(text, null);
              }
            }
            return;
          }

          if (eventType == 'message_stop') {
            if (!doneEmitted) {
              doneEmitted = true;
              await onDone?.call();
            }
          }
        } catch (_) {
          AppLogger.w("(Claude) 无法解析流式事件: event=$event, data=$data");
        }
      },
    );

    if (!doneEmitted) {
      doneEmitted = true;
      await onDone?.call();
    }
  } on GenerationAbortedException {
    AppLogger.i("(Claude) 流式请求已中断");
    rethrow;
  } catch (e, st) {
    if (_isAbortTriggered(abortController)) {
      AppLogger.i("(Claude) 流式请求在中断后关闭连接");
      throw const GenerationAbortedException();
    }
    AppLogger.e("(Claude) 流接收错误: $e\n$st");
    rethrow;
  } finally {
    client.close();
  }
}
