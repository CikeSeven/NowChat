import 'dart:async';
import 'dart:convert';
import 'package:cross_file/cross_file.dart';
import 'package:http/http.dart' as http;
import 'package:isar/isar.dart';
import 'package:logger/web.dart';
import 'package:now_chat/core/models/message.dart';
import 'package:now_chat/util/app_logger.dart';
import '../models/ai_provider_config.dart';
import '../models/chat_session.dart';

class GenerationAbortedException implements Exception {
  final String message;
  const GenerationAbortedException([
    this.message = 'generation aborted by user',
  ]);

  @override
  String toString() => message;
}

class GenerationAbortController {
  bool _aborted = false;
  final List<void Function()> _listeners = <void Function()>[];

  bool get isAborted => _aborted;

  void onAbort(void Function() listener) {
    if (_aborted) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void abort() {
    if (_aborted) return;
    _aborted = true;
    final snapshot = List<void Function()>.from(_listeners);
    _listeners.clear();
    for (final listener in snapshot) {
      listener();
    }
  }
}

class ApiService {
  static const Duration _fetchModelsTimeout = Duration(seconds: 15);
  static const int _maxFileTextChars = 12000;
  static const Set<String> _imageExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.gif',
    '.bmp',
    '.heic',
    '.heif',
  };
  static const Set<String> _textLikeExtensions = {
    '.txt',
    '.md',
    '.markdown',
    '.json',
    '.yaml',
    '.yml',
    '.xml',
    '.csv',
    '.log',
    '.ini',
    '.cfg',
    '.toml',
    '.dart',
    '.js',
    '.ts',
    '.java',
    '.kt',
    '.py',
    '.go',
    '.rs',
    '.c',
    '.cc',
    '.cpp',
    '.h',
    '.hpp',
    '.html',
    '.css',
    '.sql',
    '.sh',
    '.bat',
    '.ps1',
    '.rtf',
  };

  static String _buildOpenAIStyleModelsEndpoint(String baseUrl) {
    final normalized = baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final hasVersionTail = RegExp(
      r'/v\d+([.\-_]\d+)?$',
      caseSensitive: false,
    ).hasMatch(normalized);
    if (hasVersionTail) {
      return '$normalized/models';
    }
    return '$normalized/v1/models';
  }

  static String _normalizeBaseUrl(String? baseUrl) {
    return (baseUrl ?? '').trim().replaceAll(RegExp(r'/$'), '');
  }

  static String _resolvePath(AIProviderConfig provider) {
    final path = (provider.urlPath ?? '').trim();
    final resolved = path.isNotEmpty ? path : provider.requestMode.defaultPath;
    return _sanitizePathForMode(provider.requestMode, resolved);
  }

  static String _sanitizePathForMode(RequestMode mode, String path) {
    if (mode != RequestMode.geminiGenerateContent) return path;

    var normalized = path.replaceAll('modlels', 'models');
    if (!normalized.contains(':generateContent') &&
        !normalized.contains(':streamGenerateContent') &&
        normalized.contains('[model]')) {
      normalized = '$normalized:generateContent';
    }
    return normalized;
  }

  static Uri _buildUri(
    String baseUrl,
    String path, {
    Map<String, String>? queryParameters,
  }) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$baseUrl$normalizedPath');
    if (queryParameters == null || queryParameters.isEmpty) {
      return uri;
    }
    final merged = Map<String, String>.from(uri.queryParameters);
    merged.addAll(queryParameters);
    return uri.replace(queryParameters: merged);
  }

  static String _buildGeminiStreamingPath(String path) {
    final queryIndex = path.indexOf('?');
    final rawPath = queryIndex >= 0 ? path.substring(0, queryIndex) : path;
    final querySuffix = queryIndex >= 0 ? path.substring(queryIndex) : '';

    String streamPath = rawPath;
    if (streamPath.contains(':streamGenerateContent')) {
      return '$streamPath$querySuffix';
    }

    if (streamPath.contains(':generateContent')) {
      streamPath = streamPath.replaceFirst(
        ':generateContent',
        ':streamGenerateContent',
      );
    } else {
      streamPath =
          streamPath.endsWith('/')
              ? '${streamPath}streamGenerateContent'
              : '$streamPath:streamGenerateContent';
    }
    return '$streamPath$querySuffix';
  }

  static String _extractGeminiTextFromChunk(Map<String, dynamic> payload) {
    final candidates = payload['candidates'];
    if (candidates is! List || candidates.isEmpty) return '';

    final candidate = candidates.first;
    if (candidate is! Map) return '';

    final content = candidate['content'];
    if (content is! Map) return '';

    final parts = content['parts'];
    if (parts is! List || parts.isEmpty) return '';

    return parts
        .map((part) {
          if (part is Map) {
            return part['text']?.toString() ?? '';
          }
          return '';
        })
        .where((text) => text.isNotEmpty)
        .join();
  }

  static Future<void> _consumeSseEvents({
    required Stream<String> source,
    required FutureOr<void> Function(String event, String data) onEvent,
  }) async {
    String buffer = '';
    String? currentEvent;
    final List<String> dataLines = <String>[];

    Future<void> emitCurrentEvent() async {
      if (currentEvent == null && dataLines.isEmpty) return;
      final event = (currentEvent ?? '').trim();
      final data = dataLines.join('\n');
      currentEvent = null;
      dataLines.clear();
      await onEvent(event, data);
    }

    await for (final chunk in source) {
      buffer += chunk;
      while (true) {
        final newlineIndex = buffer.indexOf('\n');
        if (newlineIndex == -1) break;

        var line = buffer.substring(0, newlineIndex);
        buffer = buffer.substring(newlineIndex + 1);
        if (line.endsWith('\r')) {
          line = line.substring(0, line.length - 1);
        }

        if (line.isEmpty) {
          await emitCurrentEvent();
          continue;
        }
        if (line.startsWith(':')) continue;

        if (line.startsWith('event:')) {
          currentEvent = line.substring(6).trim();
          continue;
        }

        if (line.startsWith('data:')) {
          dataLines.add(line.substring(5).trimLeft());
        }
      }
    }

    final tail = buffer.trim();
    if (tail.isNotEmpty) {
      if (tail.startsWith('event:')) {
        currentEvent = tail.substring(6).trim();
      } else if (tail.startsWith('data:')) {
        dataLines.add(tail.substring(5).trimLeft());
      } else {
        dataLines.add(tail);
      }
    }
    await emitCurrentEvent();
  }

  static String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    if (index == -1 || index == normalized.length - 1) {
      return normalized;
    }
    return normalized.substring(index + 1);
  }

  static String _fileExtension(String path) {
    final lower = path.toLowerCase();
    final dotIndex = lower.lastIndexOf('.');
    if (dotIndex == -1) return '';
    return lower.substring(dotIndex);
  }

  static bool _isImageAttachmentPath(String path) {
    return _imageExtensions.contains(_fileExtension(path));
  }

  static bool _isTextLikeFile(String path) {
    return _textLikeExtensions.contains(_fileExtension(path));
  }

  static String _mimeTypeFromPath(String path) {
    switch (_fileExtension(path)) {
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      case '.bmp':
        return 'image/bmp';
      case '.heic':
        return 'image/heic';
      case '.heif':
        return 'image/heif';
      case '.pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  static List<String> _attachmentsOf(Message message) {
    return (message.imagePaths ?? const <String>[])
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static Future<String?> _readAttachmentAsTextSnippet(String path) async {
    if (!_isTextLikeFile(path)) return null;
    try {
      final text = await XFile(path).readAsString();
      if (text.isEmpty) return null;
      final normalized = text.replaceAll('\r\n', '\n');
      if (normalized.length <= _maxFileTextChars) return normalized;
      return '${normalized.substring(0, _maxFileTextChars)}\n...(已截断)';
    } catch (_) {
      return null;
    }
  }

  static Future<String> _buildFileAttachmentText(String path) async {
    final name = _fileNameFromPath(path);
    final snippet = await _readAttachmentAsTextSnippet(path);
    if (snippet != null && snippet.trim().isNotEmpty) {
      return '[文件: $name]\n$snippet';
    }
    return '[文件: $name]（无法读取文本内容，请根据文件名理解上下文）';
  }

  static bool _supportsVisionForSessionModel(
    AIProviderConfig provider,
    ChatSession session,
  ) {
    final selectedModel = (session.model ?? '').trim();
    if (selectedModel.isEmpty) return false;
    return provider.featuresForModel(selectedModel).supportsVision;
  }

  static String? _resolvedSystemPrompt(ChatSession session) {
    final prompt = (session.systemPrompt ?? '').trim();
    if (prompt.isEmpty) return null;
    return prompt;
  }

  static Map<String, dynamic>? _buildGeminiSystemInstruction(String? prompt) {
    final normalized = (prompt ?? '').trim();
    if (normalized.isEmpty) return null;
    return {
      'parts': [
        {'text': normalized},
      ],
    };
  }

  static Future<List<dynamic>> _buildOpenAIContentParts(
    Message message, {
    required bool allowVision,
  }) async {
    final parts = <dynamic>[];
    final text = message.content.trim();
    if (text.isNotEmpty) {
      parts.add({'type': 'text', 'text': text});
    }

    final attachments = _attachmentsOf(message);
    if (attachments.isEmpty) return parts;

    for (final path in attachments) {
      if (_isImageAttachmentPath(path)) {
        if (!allowVision) {
          parts.add({
            'type': 'text',
            'text': '[图片: ${_fileNameFromPath(path)}]（当前模型未开启视觉能力）',
          });
          continue;
        }
        try {
          final bytes = await XFile(path).readAsBytes();
          final mimeType = _mimeTypeFromPath(path);
          final base64Data = base64Encode(bytes);
          parts.add({
            'type': 'image_url',
            'image_url': {'url': 'data:$mimeType;base64,$base64Data'},
          });
        } catch (_) {
          parts.add({
            'type': 'text',
            'text': '[图片: ${_fileNameFromPath(path)}]（读取失败）',
          });
        }
      } else {
        parts.add({
          'type': 'text',
          'text': await _buildFileAttachmentText(path),
        });
      }
    }

    return parts;
  }

  static Future<List<Map<String, dynamic>>> _buildOpenAIMessagesPayload(
    List<Message> messages, {
    required bool allowVision,
    String? systemPrompt,
  }) async {
    final payload = <Map<String, dynamic>>[];
    final normalizedSystemPrompt = systemPrompt?.trim() ?? '';
    if (normalizedSystemPrompt.isNotEmpty) {
      payload.add({'role': 'system', 'content': normalizedSystemPrompt});
    }
    for (final message in messages) {
      final attachments = _attachmentsOf(message);
      if (attachments.isEmpty) {
        payload.add({'role': message.role, 'content': message.content});
        continue;
      }

      final contentParts = await _buildOpenAIContentParts(
        message,
        allowVision: allowVision,
      );
      if (contentParts.isEmpty) {
        payload.add({'role': message.role, 'content': message.content});
      } else {
        payload.add({'role': message.role, 'content': contentParts});
      }
    }
    return payload;
  }

  static Future<List<dynamic>> _buildGeminiParts(
    Message message, {
    required bool allowVision,
  }) async {
    final parts = <dynamic>[];
    final text = message.content.trim();
    if (text.isNotEmpty) {
      parts.add({'text': text});
    }

    final attachments = _attachmentsOf(message);
    if (attachments.isEmpty) return parts;

    for (final path in attachments) {
      if (_isImageAttachmentPath(path)) {
        if (!allowVision) {
          parts.add({'text': '[图片: ${_fileNameFromPath(path)}]（当前模型未开启视觉能力）'});
          continue;
        }
        try {
          final bytes = await XFile(path).readAsBytes();
          final mimeType = _mimeTypeFromPath(path);
          parts.add({
            'inlineData': {'mimeType': mimeType, 'data': base64Encode(bytes)},
          });
        } catch (_) {
          parts.add({'text': '[图片: ${_fileNameFromPath(path)}]（读取失败）'});
        }
      } else {
        parts.add({'text': await _buildFileAttachmentText(path)});
      }
    }
    return parts;
  }

  static Future<List<Map<String, dynamic>>> _buildGeminiContentsPayload(
    List<Message> messages, {
    required bool allowVision,
  }) async {
    final contents = <Map<String, dynamic>>[];
    for (final message in messages) {
      final role = message.role == 'assistant' ? 'model' : 'user';
      final parts = await _buildGeminiParts(message, allowVision: allowVision);
      if (parts.isEmpty) continue;
      contents.add({'role': role, 'parts': parts});
    }
    return contents;
  }

  static Future<dynamic> _buildClaudeContent(
    Message message, {
    required bool allowVision,
  }) async {
    final blocks = <dynamic>[];
    final text = message.content.trim();
    if (text.isNotEmpty) {
      blocks.add({'type': 'text', 'text': text});
    }

    final attachments = _attachmentsOf(message);
    if (attachments.isEmpty) {
      return message.content;
    }

    for (final path in attachments) {
      if (_isImageAttachmentPath(path)) {
        if (!allowVision) {
          blocks.add({
            'type': 'text',
            'text': '[图片: ${_fileNameFromPath(path)}]（当前模型未开启视觉能力）',
          });
          continue;
        }
        try {
          final bytes = await XFile(path).readAsBytes();
          blocks.add({
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': _mimeTypeFromPath(path),
              'data': base64Encode(bytes),
            },
          });
        } catch (_) {
          blocks.add({
            'type': 'text',
            'text': '[图片: ${_fileNameFromPath(path)}]（读取失败）',
          });
        }
      } else {
        blocks.add({
          'type': 'text',
          'text': await _buildFileAttachmentText(path),
        });
      }
    }
    return blocks;
  }

  static Future<List<Map<String, dynamic>>> _buildClaudeMessagesPayload(
    List<Message> messages, {
    required bool allowVision,
  }) async {
    final payload = <Map<String, dynamic>>[];
    for (final message in messages) {
      final role = message.role == 'assistant' ? 'assistant' : 'user';
      payload.add({
        'role': role,
        'content': await _buildClaudeContent(message, allowVision: allowVision),
      });
    }
    return payload;
  }

  static String _resolveModel(AIProviderConfig provider, ChatSession session) {
    final selected = (session.model ?? '').trim();
    if (selected.isNotEmpty) return selected;
    if (provider.models.isNotEmpty) return provider.models.first;
    throw Exception('未选择模型，请先在会话中选择模型');
  }

  static Future<List<Message>> _loadFilteredMessages(
    Isar isar,
    ChatSession session,
  ) async {
    final messages =
        await isar.messages
            .filter()
            .chatIdEqualTo(session.id)
            .sortByTimestamp()
            .findAll();

    return _filterMessagesForRequest(messages);
  }

  static List<Message> _filterMessagesForRequest(List<Message> messages) {
    return messages
        .where(
          (m) =>
              m.role != 'assistant' ||
              (m.content.isNotEmpty && m.content.trim().isNotEmpty),
        )
        .toList();
  }

  static Future<List<Message>> _resolveRequestMessages(
    Isar isar,
    ChatSession session, {
    List<Message>? overrideMessages,
  }) async {
    if (overrideMessages != null) {
      return _filterMessagesForRequest(overrideMessages);
    }
    return _loadFilteredMessages(isar, session);
  }

  static bool _isAbortTriggered(GenerationAbortController? controller) {
    return controller?.isAborted ?? false;
  }

  // 流式对话
  static Future<void> sendChatRequestStreaming({
    required AIProviderConfig provider,
    required ChatSession session,
    required Isar isar,
    GenerationAbortController? abortController,
    List<Message>? overrideMessages,
    FutureOr<void> Function(String deltaContent, String? deltaReasoning)?
    onStream,
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

  static Future<void> _sendOpenAIChatStreaming({
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
    abortController?.onAbort(() {
      client.close();
    });
    final filteredMessages = await _resolveRequestMessages(
      isar,
      session,
      overrideMessages: overrideMessages,
    );
    bool doneEmitted = false;

    try {
      if (abortController?.isAborted ?? false) {
        throw const GenerationAbortedException();
      }
      final base = _normalizeBaseUrl(provider.baseUrl);
      final path = _resolvePath(provider);
      final uri = _buildUri(base, path);
      final model = _resolveModel(provider, session);
      final allowVision = _supportsVisionForSessionModel(provider, session);
      final systemPrompt = _resolvedSystemPrompt(session);

      final headers = {'Content-Type': 'application/json'};
      final apiKey = (provider.apiKey ?? '').trim();
      if (apiKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer $apiKey';
      }

      final body = {
        'model': model,
        'messages': await _buildOpenAIMessagesPayload(
          filteredMessages,
          allowVision: allowVision,
          systemPrompt: systemPrompt,
        ),
        'temperature': session.temperature,
        'top_p': session.topP,
        'max_tokens': session.maxTokens,
        'stream': true,
      };

      AppLogger.i("发起流式请求 → $uri");
      AppLogger.i("请求体：$body");

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
      String buffer = '';

      await for (final chunk in utf8Stream) {
        if (abortController?.isAborted ?? false) {
          throw const GenerationAbortedException();
        }
        buffer += chunk;
        while (true) {
          if (abortController?.isAborted ?? false) {
            throw const GenerationAbortedException();
          }
          final newlineIndex = buffer.indexOf('\n');
          if (newlineIndex == -1) break;

          var line = buffer.substring(0, newlineIndex).trim();
          buffer = buffer.substring(newlineIndex + 1);
          if (line.isEmpty) continue;

          if (line == '[DONE]' || line == 'data: [DONE]') {
            AppLogger.i('流式响应完成');
            if (!doneEmitted) {
              doneEmitted = true;
              await onDone?.call();
            }
            continue;
          }

          if (line.startsWith('data:')) {
            line = line.substring(5).trim();
          }

          try {
            final jsonData = jsonDecode(line);
            if (jsonData is! Map<String, dynamic>) continue;

            final choices = jsonData['choices'];
            if (choices is! List || choices.isEmpty) {
              // Some providers emit usage/heartbeat chunks with empty choices.
              continue;
            }

            final firstChoice = choices.first;
            if (firstChoice is! Map) continue;
            final delta = firstChoice['delta'];
            if (delta is! Map) continue;

            final reasoningRaw =
                delta['reasoning_content'] ?? delta['reasoning'];
            final contentRaw = delta['content'];
            final reasoning = reasoningRaw is String ? reasoningRaw : null;
            final content = contentRaw is String ? contentRaw : '';

            if (content.isNotEmpty || (reasoning?.isNotEmpty ?? false)) {
              await onStream?.call(content, reasoning);
            }
          } catch (_) {
            AppLogger.w("无法解析 JSON 行：$line");
          }
        }
      }
      AppLogger.i('流式请求结束');
      if (!doneEmitted) {
        AppLogger.i('未收到 [DONE]，按流结束补发完成回调');
        doneEmitted = true;
        await onDone?.call();
      }
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

  static Future<void> _sendGeminiRequestStreaming({
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
    abortController?.onAbort(() {
      client.close();
    });
    bool doneEmitted = false;
    String? lastSnapshot;

    try {
      if (abortController?.isAborted ?? false) {
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
      final geminiSystemInstruction = _buildGeminiSystemInstruction(
        systemPrompt,
      );
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
          'maxOutputTokens': session.maxTokens,
        },
      };

      AppLogger.i("(Gemini) 发起流式请求 → $uri");
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
          if (abortController?.isAborted ?? false) {
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

            String delta = chunkText;
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

  static Future<void> _sendClaudeRequestStreaming({
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
    abortController?.onAbort(() {
      client.close();
    });
    bool doneEmitted = false;

    try {
      if (abortController?.isAborted ?? false) {
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
        'max_tokens': session.maxTokens,
        'temperature': session.temperature,
        'top_p': session.topP,
        'messages': messages,
        if (systemPrompt != null) 'system': systemPrompt,
        'stream': true,
      };

      AppLogger.i("(Claude) 发起流式请求 → $uri");
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
          if (abortController?.isAborted ?? false) {
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

  // 非流式对话
  static Future<Map<String, dynamic>> sendChatRequest({
    required AIProviderConfig provider,
    required ChatSession session,
    required Isar isar,
    GenerationAbortController? abortController,
    List<Message>? overrideMessages,
  }) async {
    switch (provider.requestMode) {
      case RequestMode.openaiChat:
        return _sendOpenAIChatRequest(
          provider: provider,
          session: session,
          isar: isar,
          abortController: abortController,
          overrideMessages: overrideMessages,
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

  static Future<Map<String, dynamic>> _sendOpenAIChatRequest({
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
    final filteredMessages = await _resolveRequestMessages(
      isar,
      session,
      overrideMessages: overrideMessages,
    );
    final allowVision = _supportsVisionForSessionModel(provider, session);
    final systemPrompt = _resolvedSystemPrompt(session);

    final headers = {'Content-Type': 'application/json'};
    final apiKey = (provider.apiKey ?? '').trim();
    if (apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }

    final body = {
      'model': model,
      'messages': await _buildOpenAIMessagesPayload(
        filteredMessages,
        allowVision: allowVision,
        systemPrompt: systemPrompt,
      ),
      'temperature': session.temperature,
      'top_p': session.topP,
      'max_tokens': session.maxTokens,
    };

    logger.i("(OpenAI) 向 $uri 发送对话请求");
    final client = http.Client();
    abortController?.onAbort(() {
      client.close();
    });
    try {
      if (abortController?.isAborted ?? false) {
        throw const GenerationAbortedException();
      }
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
      final content =
          data['choices']?[0]?['message']?['content'] ??
          data['output'] ??
          data['response'] ??
          data['message'] ??
          '（无返回内容）';

      return {'content': content, 'reasoning': null, 'reasoningTimeMs': null};
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

  static Future<Map<String, dynamic>> _sendGeminiRequest({
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
        'maxOutputTokens': session.maxTokens,
      },
    };

    logger.i("(Gemini) 向 $uri 发送对话请求");
    final client = http.Client();
    abortController?.onAbort(() {
      client.close();
    });
    try {
      if (abortController?.isAborted ?? false) {
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

  static Future<Map<String, dynamic>> _sendClaudeRequest({
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
      'max_tokens': session.maxTokens,
      'temperature': session.temperature,
      'top_p': session.topP,
      'messages': messages,
      if (systemPrompt != null) 'system': systemPrompt,
    };

    logger.i("(Claude) 向 $uri 发送对话请求");
    final client = http.Client();
    abortController?.onAbort(() {
      client.close();
    });
    try {
      if (abortController?.isAborted ?? false) {
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

  // 获取模型列表
  static Future<List<String>> fetchModels(
    AIProviderConfig provider,
    String baseUrl,
    String apiKey,
  ) async {
    final logger = Logger();

    String urlPath = "";
    switch (provider.type) {
      case ProviderType.openai:
      case ProviderType.deepseek:
      case ProviderType.openaiCompatible:
        urlPath = _buildOpenAIStyleModelsEndpoint(baseUrl);
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
    final http.Response response;
    try {
      response = await http
          .get(url, headers: headers)
          .timeout(_fetchModelsTimeout);
    } on TimeoutException {
      throw Exception(
        '获取模型列表超时（${_fetchModelsTimeout.inSeconds} 秒），请检查网络或接口地址',
      );
    }
    logger.i("返回体：${response.body}");

    if (response.statusCode == 200) {
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
    } else {
      throw Exception("请求失败 (${response.statusCode}): ${response.body}");
    }
  }
}
