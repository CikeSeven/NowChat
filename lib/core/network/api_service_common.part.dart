part of 'api_service.dart';

/// API 通用工具、请求构建与消息载荷转换逻辑。

const Duration _fetchModelsTimeout = Duration(seconds: 15);
const int _maxFileTextChars = 12000;

const Set<String> _imageExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.webp',
  '.gif',
  '.bmp',
  '.heic',
  '.heif',
};

const Set<String> _textLikeExtensions = <String>{
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

/// 构建 OpenAI 兼容的模型列表接口地址。
String _buildOpenAIStyleModelsEndpoint(String baseUrl) {
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

/// 规范化基础地址（去掉空白和尾部 `/`）。
String _normalizeBaseUrl(String? baseUrl) {
  return (baseUrl ?? '').trim().replaceAll(RegExp(r'/$'), '');
}

/// 解析最终请求路径，优先使用用户配置路径。
String _resolvePath(AIProviderConfig provider) {
  final path = (provider.urlPath ?? '').trim();
  final resolved = path.isNotEmpty ? path : provider.requestMode.defaultPath;
  return _sanitizePathForMode(provider.requestMode, resolved);
}

/// 针对特定协议修正路径中的常见输入错误。
String _sanitizePathForMode(RequestMode mode, String path) {
  if (mode != RequestMode.geminiGenerateContent) return path;

  var normalized = path.replaceAll('modlels', 'models');
  if (!normalized.contains(':generateContent') &&
      !normalized.contains(':streamGenerateContent') &&
      normalized.contains('[model]')) {
    normalized = '$normalized:generateContent';
  }
  return normalized;
}

/// 根据基础地址和路径拼接 URI，并合并查询参数。
Uri _buildUri(
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

/// 将 Gemini 普通路径转换为流式路径。
String _buildGeminiStreamingPath(String path) {
  final queryIndex = path.indexOf('?');
  final rawPath = queryIndex >= 0 ? path.substring(0, queryIndex) : path;
  final querySuffix = queryIndex >= 0 ? path.substring(queryIndex) : '';

  var streamPath = rawPath;
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

/// 从 Gemini 单个 chunk 提取文本。
String _extractGeminiTextFromChunk(Map<String, dynamic> payload) {
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

/// 通用 SSE 事件消费器，按 event/data 回调。
Future<void> _consumeSseEvents({
  required Stream<String> source,
  required FutureOr<void> Function(String event, String data) onEvent,
}) async {
  var buffer = '';
  String? currentEvent;
  final dataLines = <String>[];

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

/// 从文件路径提取文件名。
String _fileNameFromPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  if (index == -1 || index == normalized.length - 1) return normalized;
  return normalized.substring(index + 1);
}

/// 获取文件扩展名（小写）。
String _fileExtension(String path) {
  final lower = path.toLowerCase();
  final dotIndex = lower.lastIndexOf('.');
  if (dotIndex == -1) return '';
  return lower.substring(dotIndex);
}

/// 判断是否是图片附件。
bool _isImageAttachmentPath(String path) {
  return _imageExtensions.contains(_fileExtension(path));
}

/// 判断是否为可读文本类文件。
bool _isTextLikeFile(String path) {
  return _textLikeExtensions.contains(_fileExtension(path));
}

/// 根据扩展名映射基础 MIME 类型。
String _mimeTypeFromPath(String path) {
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

/// 获取消息中的附件路径列表。
List<String> _attachmentsOf(Message message) {
  return (message.imagePaths ?? const <String>[])
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

/// 读取文本附件片段，过长时截断。
Future<String?> _readAttachmentAsTextSnippet(String path) async {
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

/// 将非图片附件转为可发送文本描述。
Future<String> _buildFileAttachmentText(String path) async {
  final name = _fileNameFromPath(path);
  final snippet = await _readAttachmentAsTextSnippet(path);
  if (snippet != null && snippet.trim().isNotEmpty) {
    return '[文件: $name]\n$snippet';
  }
  return '[文件: $name]（无法读取文本内容，请根据文件名理解上下文）';
}

/// 判断当前会话选中模型是否支持视觉。
bool _supportsVisionForSessionModel(
  AIProviderConfig provider,
  ChatSession session,
) {
  final selectedModel = (session.model ?? '').trim();
  if (selectedModel.isEmpty) return false;
  return provider.featuresForModel(selectedModel).supportsVision;
}

/// 获取当前会话有效系统提示词。
String? _resolvedSystemPrompt(ChatSession session) {
  final prompt = (session.systemPrompt ?? '').trim();
  if (prompt.isEmpty) return null;
  return prompt;
}

/// 构建 Gemini `systemInstruction` 结构。
Map<String, dynamic>? _buildGeminiSystemInstruction(String? prompt) {
  final normalized = (prompt ?? '').trim();
  if (normalized.isEmpty) return null;
  return {
    'parts': [
      {'text': normalized},
    ],
  };
}

/// 构建 OpenAI 消息 `content` 多模态分片。
Future<List<dynamic>> _buildOpenAIContentParts(
  Message message, {
  required bool allowVision,
}) async {
  final parts = <dynamic>[];
  final text = message.content.trim();
  if (text.isNotEmpty) {
    parts.add({'type': 'text', 'text': text});
  }

  for (final path in _attachmentsOf(message)) {
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
        parts.add({
          'type': 'image_url',
          'image_url': {'url': 'data:$mimeType;base64,${base64Encode(bytes)}'},
        });
      } catch (_) {
        parts.add({
          'type': 'text',
          'text': '[图片: ${_fileNameFromPath(path)}]（读取失败）',
        });
      }
      continue;
    }
    parts.add({'type': 'text', 'text': await _buildFileAttachmentText(path)});
  }

  return parts;
}

/// 构建 OpenAI 风格的消息数组载荷。
Future<List<Map<String, dynamic>>> _buildOpenAIMessagesPayload(
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
    payload.add({'role': message.role, 'content': contentParts});
  }
  return payload;
}

/// 构建 Gemini 单条消息 `parts`。
Future<List<dynamic>> _buildGeminiParts(
  Message message, {
  required bool allowVision,
}) async {
  final parts = <dynamic>[];
  final text = message.content.trim();
  if (text.isNotEmpty) parts.add({'text': text});

  for (final path in _attachmentsOf(message)) {
    if (_isImageAttachmentPath(path)) {
      if (!allowVision) {
        parts.add({'text': '[图片: ${_fileNameFromPath(path)}]（当前模型未开启视觉能力）'});
        continue;
      }
      try {
        final bytes = await XFile(path).readAsBytes();
        parts.add({
          'inlineData': {
            'mimeType': _mimeTypeFromPath(path),
            'data': base64Encode(bytes),
          },
        });
      } catch (_) {
        parts.add({'text': '[图片: ${_fileNameFromPath(path)}]（读取失败）'});
      }
      continue;
    }
    parts.add({'text': await _buildFileAttachmentText(path)});
  }
  return parts;
}

/// 构建 Gemini `contents` 载荷。
Future<List<Map<String, dynamic>>> _buildGeminiContentsPayload(
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

/// 构建 Claude 单条消息 `content`。
Future<dynamic> _buildClaudeContent(
  Message message, {
  required bool allowVision,
}) async {
  final blocks = <dynamic>[];
  final text = message.content.trim();
  if (text.isNotEmpty) blocks.add({'type': 'text', 'text': text});

  final attachments = _attachmentsOf(message);
  if (attachments.isEmpty) return message.content;

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
      continue;
    }
    blocks.add({'type': 'text', 'text': await _buildFileAttachmentText(path)});
  }
  return blocks;
}

/// 构建 Claude `messages` 载荷。
Future<List<Map<String, dynamic>>> _buildClaudeMessagesPayload(
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

/// 解析当前请求使用的模型名。
String _resolveModel(AIProviderConfig provider, ChatSession session) {
  final selected = (session.model ?? '').trim();
  if (selected.isNotEmpty) return selected;
  if (provider.models.isNotEmpty) return provider.models.first;
  throw Exception('未选择模型，请先在会话中选择模型');
}

/// 从数据库加载并过滤当前会话消息。
Future<List<Message>> _loadFilteredMessages(
  Isar isar,
  ChatSession session,
) async {
  final messages =
      await isar.messages
          .filter()
          .chatIdEqualTo(session.id)
          .sortByTimestamp()
          .findAll();
  final filtered = _filterMessagesForRequest(messages);
  return _applyConversationTurnLimit(filtered, session.maxConversationTurns);
}

/// 过滤无效 assistant 消息，避免污染上下文。
List<Message> _filterMessagesForRequest(List<Message> messages) {
  return messages
      .where(
        (m) =>
            m.role != 'assistant' ||
            (m.content.isNotEmpty && m.content.trim().isNotEmpty),
      )
      .toList();
}

/// 按“用户 + AI 回复”为 1 轮，截取最近 N 轮消息。
List<Message> _applyConversationTurnLimit(
  List<Message> messages,
  int maxConversationTurns,
) {
  if (maxConversationTurns <= 0 || messages.isEmpty) {
    return messages;
  }

  final rounds = <List<Message>>[];
  var currentRound = <Message>[];

  for (final message in messages) {
    if (message.role == 'user') {
      if (currentRound.isNotEmpty) {
        rounds.add(currentRound);
      }
      currentRound = <Message>[message];
      continue;
    }

    if (currentRound.isEmpty) {
      rounds.add(<Message>[message]);
      continue;
    }
    currentRound.add(message);
  }

  if (currentRound.isNotEmpty) {
    rounds.add(currentRound);
  }

  if (rounds.length <= maxConversationTurns) {
    return messages;
  }

  final start = rounds.length - maxConversationTurns;
  return rounds
      .sublist(start)
      .expand((round) => round)
      .toList(growable: false);
}

/// 获取本次请求使用的消息（优先覆盖列表）。
Future<List<Message>> _resolveRequestMessages(
  Isar isar,
  ChatSession session, {
  List<Message>? overrideMessages,
}) async {
  if (overrideMessages != null) {
    final filtered = _filterMessagesForRequest(overrideMessages);
    return _applyConversationTurnLimit(filtered, session.maxConversationTurns);
  }
  return _loadFilteredMessages(isar, session);
}

/// 统一判断是否触发中断。
bool _isAbortTriggered(GenerationAbortController? controller) {
  return controller?.isAborted ?? false;
}

/// 判断当前会话是否启用工具调用（需模型能力和会话开关同时满足）。
bool _isToolCallingEnabledForSession(
  AIProviderConfig provider,
  ChatSession session,
) {
  if (!session.toolCallingEnabled) return false;
  final selectedModel = (session.model ?? '').trim();
  if (selectedModel.isEmpty) return false;
  return provider.featuresForModel(selectedModel).supportsTools;
}

/// 将 OpenAI `message.content`（字符串/分片数组）提取为纯文本。
String _extractOpenAIMessageContentText(Map<String, dynamic>? message) {
  if (message == null) return '';
  final content = message['content'];
  if (content is String) return content;
  if (content is List) {
    final texts = <String>[];
    for (final item in content) {
      if (item is String && item.trim().isNotEmpty) {
        texts.add(item);
        continue;
      }
      if (item is Map) {
        final text = item['text']?.toString() ?? '';
        if (text.trim().isNotEmpty) {
          texts.add(text);
        }
      }
    }
    return texts.join('\n');
  }
  return '';
}

/// 从 OpenAI 普通响应中的 `tool_calls` 解析工具调用列表。
List<AIToolCall> _parseOpenAIToolCallsFromMessage(dynamic message) {
  if (message is! Map) return const <AIToolCall>[];
  final rawToolCalls = message['tool_calls'];
  if (rawToolCalls is! List || rawToolCalls.isEmpty) {
    return const <AIToolCall>[];
  }
  final toolCalls = <AIToolCall>[];
  for (final raw in rawToolCalls) {
    if (raw is! Map) continue;
    final functionRaw = raw['function'];
    if (functionRaw is! Map) continue;
    final id = (raw['id'] ?? '').toString().trim();
    final name = (functionRaw['name'] ?? '').toString().trim();
    final arguments = (functionRaw['arguments'] ?? '').toString();
    if (id.isEmpty || name.isEmpty) continue;
    toolCalls.add(AIToolCall(id: id, name: name, rawArguments: arguments));
  }
  return toolCalls;
}

/// 构建 OpenAI assistant 消息里的 `tool_calls` 载荷。
Map<String, dynamic> _toOpenAIToolCallPayload(AIToolCall call) {
  return <String, dynamic>{
    'id': call.id,
    'type': 'function',
    'function': <String, dynamic>{
      'name': call.name,
      'arguments': call.rawArguments,
    },
  };
}

/// 流式 tool_call 增量聚合器。
class _StreamingToolCallBuilder {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();
}

/// 合并 OpenAI 流式响应中的 `delta.tool_calls` 增量。
void _mergeOpenAIStreamingToolCalls(
  List<dynamic> toolCallsRaw,
  Map<int, _StreamingToolCallBuilder> builders,
) {
  for (final raw in toolCallsRaw) {
    if (raw is! Map) continue;
    final indexRaw = raw['index'];
    if (indexRaw is! num) continue;
    final index = indexRaw.toInt();
    final builder =
        builders.putIfAbsent(index, () => _StreamingToolCallBuilder());

    final id = (raw['id'] ?? '').toString().trim();
    if (id.isNotEmpty) {
      builder.id = id;
    }

    final functionRaw = raw['function'];
    if (functionRaw is Map) {
      final name = (functionRaw['name'] ?? '').toString().trim();
      if (name.isNotEmpty) {
        builder.name = name;
      }
      final argumentsChunk = (functionRaw['arguments'] ?? '').toString();
      if (argumentsChunk.isNotEmpty) {
        builder.arguments.write(argumentsChunk);
      }
    }
  }
}

/// 将流式聚合结果转换为稳定的工具调用列表。
List<AIToolCall> _finalizeOpenAIStreamingToolCalls(
  Map<int, _StreamingToolCallBuilder> builders,
) {
  if (builders.isEmpty) return const <AIToolCall>[];
  final entries =
      builders.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  final result = <AIToolCall>[];
  for (final entry in entries) {
    final builder = entry.value;
    final id = builder.id.trim();
    final name = builder.name.trim();
    if (id.isEmpty || name.isEmpty) continue;
    result.add(
      AIToolCall(
        id: id,
        name: name,
        rawArguments: builder.arguments.toString(),
      ),
    );
  }
  return result;
}
