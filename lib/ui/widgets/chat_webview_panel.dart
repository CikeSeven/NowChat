import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:now_chat/core/models/chat_session.dart';
import 'package:now_chat/core/models/message.dart';
import 'package:now_chat/core/models/tool_execution_log.dart';
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';

/// 本地图片代理服务器（单例），为 WebView 提供本地文件访问能力。
class _LocalImageServer {
  static _LocalImageServer? _instance;
  HttpServer? _server;
  int get port => _server?.port ?? 0;
  bool get isRunning => _server != null;

  _LocalImageServer._();

  static _LocalImageServer get instance {
    _instance ??= _LocalImageServer._();
    return _instance!;
  }

  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleRequest);
  }

  void _handleRequest(HttpRequest request) async {
    try {
      // 仅暴露单一代理端点，避免误请求时返回不明确结果。
      if (request.uri.path != '/local-image') {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found')
          ..close();
        return;
      }

      final filePath = request.uri.queryParameters['path'];
      if (filePath == null || filePath.isEmpty) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('Missing path parameter')
          ..close();
        return;
      }
      final normalizedPath = _normalizeIncomingPath(filePath);
      final file = File(normalizedPath);
      if (!await file.exists()) {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('File not found')
          ..close();
        return;
      }
      final ext = p.extension(normalizedPath).toLowerCase().replaceFirst('.', '');
      const mimeMap = {
        'png': 'image/png',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'gif': 'image/gif',
        'webp': 'image/webp',
        'bmp': 'image/bmp',
        'heic': 'image/heic',
        'heif': 'image/heif',
      };
      final mime = mimeMap[ext] ?? 'application/octet-stream';
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.parse(mime)
        // 聊天消息中的图片可能会被频繁刷新，禁用缓存避免旧图残留。
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..headers.set('Access-Control-Allow-Origin', '*');
      await request.response.addStream(file.openRead());
      await request.response.close();
    } catch (e) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write('Error: $e')
        ..close();
    }
  }

  /// 统一处理 query 参数中的文件路径，兼容 file:// URI 与百分号编码路径。
  String _normalizeIncomingPath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.startsWith('file://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null && uri.scheme == 'file') {
        try {
          return uri.toFilePath(windows: Platform.isWindows);
        } catch (_) {
          // 忽略解析失败，回退到原始字符串。
        }
      }
    }
    try {
      return Uri.decodeFull(trimmed);
    } catch (_) {
      return trimmed;
    }
  }

  /// 将本地文件路径转为代理 URL。
  String proxyUrl(String localPath) {
    final encoded = Uri.encodeQueryComponent(localPath);
    return 'http://127.0.0.1:$port/local-image?path=$encoded';
  }
}

/// WebView 聊天面板，承载消息列表 + 输入框。
///
/// 通过 JavaScriptChannel 与 JS 侧双向通信，
/// Flutter 侧通过 [evaluateJavascript] 调用 JS 方法推送数据。
class ChatWebViewPanel extends StatefulWidget {
  final ChatSession? chat;
  final List<Message> messages;
  final String? model;
  final bool isGenerating;
  final bool modelSupportsVision;
  final bool modelSupportsTools;
  final bool isStreaming;
  final bool streamingSupported;
  final String systemPrompt;
  final List<String> attachments;
  final bool isLoadingMoreHistory;

  // Callbacks
  final void Function(String text) onSendMessage;
  final VoidCallback? onStopGenerating;
  final VoidCallback? onPickImage;
  final VoidCallback? onPickFile;
  final ValueChanged<String>? onRemoveAttachment;
  final VoidCallback? onSelectModel;
  final ValueChanged<bool>? onStreamingChanged;
  final VoidCallback? onScrollNearTop;
  final void Function(int id, String action) onMessageAction;
  final void Function(String url) onLinkTap;
  final void Function(String url) onImageTap;
  final VoidCallback? onShowAttachmentMenu;
  final void Function(int id)? onUserMessageLongPress;

  // 流式状态查询
  final bool Function(int messageId) isMessageStreaming;
  final bool Function(int messageId) canContinueAssistantMessage;
  final List<ToolExecutionLog> Function(int messageId) toolLogsForMessage;

  const ChatWebViewPanel({
    super.key,
    required this.chat,
    required this.messages,
    required this.model,
    required this.isGenerating,
    this.modelSupportsVision = false,
    this.modelSupportsTools = false,
    required this.isStreaming,
    required this.streamingSupported,
    required this.systemPrompt,
    this.attachments = const [],
    this.isLoadingMoreHistory = false,
    required this.onSendMessage,
    this.onStopGenerating,
    this.onPickImage,
    this.onPickFile,
    this.onRemoveAttachment,
    this.onSelectModel,
    this.onStreamingChanged,
    this.onScrollNearTop,
    required this.onMessageAction,
    required this.onLinkTap,
    required this.onImageTap,
    this.onShowAttachmentMenu,
    this.onUserMessageLongPress,
    required this.isMessageStreaming,
    required this.canContinueAssistantMessage,
    required this.toolLogsForMessage,
  });

  @override
  State<ChatWebViewPanel> createState() => _ChatWebViewPanelState();
}

class _ChatWebViewPanelState extends State<ChatWebViewPanel> {
  late final WebViewController _controller;
  bool _webViewReady = false;
  bool _htmlLoading = false;

  /// 上一次同步到 WebView 的消息快照，用于增量更新。
  List<int> _syncedMessageIds = [];
  /// 上一次同步的消息内容长度，用于检测流式更新。
  final Map<int, int> _syncedContentLengths = {};
  final Map<int, int> _syncedReasoningLengths = {};
  final Map<int, int> _syncedToolLogCounts = {};

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: _handleJsMessage,
      );
    // 启动本地图片代理服务器
    _LocalImageServer.instance.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_webViewReady && !_htmlLoading) {
      _htmlLoading = true;
      _controller.setBackgroundColor(Theme.of(context).colorScheme.surface);
      _loadHtmlFromAssets();
    }
  }

  Future<void> _loadHtmlFromAssets() async {
    // 确保图片代理服务器已启动
    await _LocalImageServer.instance.start();

    final html = await rootBundle.loadString('assets/chat_webview/index.html');
    final css = await rootBundle.loadString('assets/chat_webview/style.css');
    final bridgeJs =
        await rootBundle.loadString('assets/chat_webview/bridge.js');
    final chatJs =
        await rootBundle.loadString('assets/chat_webview/chat.js');

    // 内联所有资源到单个 HTML，避免 WebView 相对路径问题
    final inlinedHtml = html
        .replaceFirst(
          '<link rel="stylesheet" href="style.css">',
          '<style>$css</style>',
        )
        .replaceFirst(
          '<script src="bridge.js"></script>',
          '<script>$bridgeJs</script>',
        )
        .replaceFirst(
          '<script src="chat.js"></script>',
          '<script>$chatJs</script>',
        );

    await _controller.loadHtmlString(inlinedHtml);
  }

  // ===== JS → Flutter 消息处理 =====
  void _handleJsMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final action = data['action'] as String?;
      switch (action) {
        case 'onReady':
          _webViewReady = true;
          _syncFullState();
          break;
        case 'onSendMessage':
          widget.onSendMessage(data['text'] as String? ?? '');
          break;
        case 'onStopGenerating':
          widget.onStopGenerating?.call();
          break;
        case 'onPickImage':
          widget.onPickImage?.call();
          break;
        case 'onPickFile':
          widget.onPickFile?.call();
          break;
        case 'onRemoveAttachment':
          widget.onRemoveAttachment?.call(data['path'] as String? ?? '');
          break;
        case 'onLinkTap':
          widget.onLinkTap(data['url'] as String? ?? '');
          break;
        case 'onImageTap':
          widget.onImageTap(data['url'] as String? ?? '');
          break;
        case 'onScrollNearTop':
          widget.onScrollNearTop?.call();
          break;
        case 'onToggleStreaming':
          widget.onStreamingChanged?.call(data['value'] as bool? ?? true);
          break;
        case 'onSelectModel':
          widget.onSelectModel?.call();
          break;
        case 'onMessageAction':
          final id = data['id'] as int? ?? 0;
          final act = data['msgAction'] as String? ?? '';
          widget.onMessageAction(id, act);
          break;
        case 'onShowAttachmentMenu':
          widget.onShowAttachmentMenu?.call();
          break;
        case 'onUserMessageLongPress':
          final id = data['id'] as int? ?? 0;
          widget.onUserMessageLongPress?.call(id);
          break;
      }
    } catch (e) {
      debugPrint('ChatWebViewPanel: JS message parse error: $e');
    }
  }

  // ===== 状态同步 =====

  @override
  void didUpdateWidget(covariant ChatWebViewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_webViewReady) return;

    // 消息变化 → 增量同步（不做引用相等判断，因为 Provider 可能返回同一个可变列表实例）
    _syncMessages();

    // 生成状态
    if (widget.isGenerating != oldWidget.isGenerating) {
      _evalJs(
        'ChatBridge.setGeneratingState(${widget.isGenerating})',
      );
    }

    // 模型信息
    if (widget.model != oldWidget.model ||
        widget.modelSupportsVision != oldWidget.modelSupportsVision ||
        widget.modelSupportsTools != oldWidget.modelSupportsTools) {
      _evalJs(
        "ChatBridge.setModelInfo('${_escJs(widget.model ?? '')}', ${widget.modelSupportsVision}, ${widget.modelSupportsTools})",
      );
    }

    // 流式开关
    if (widget.isStreaming != oldWidget.isStreaming ||
        widget.streamingSupported != oldWidget.streamingSupported) {
      _evalJs(
        'ChatBridge.setStreamingState(${widget.isStreaming}, ${widget.streamingSupported})',
      );
    }

    // 附件
    if (widget.attachments != oldWidget.attachments) {
      _evalJs(
        "ChatBridge.setAttachments('${_escJs(jsonEncode(widget.attachments))}')",
      );
    }

    // 系统提示词
    if (widget.systemPrompt != oldWidget.systemPrompt) {
      _evalJs(
        "ChatBridge.setSystemPrompt('${_escJs(widget.systemPrompt)}')",
      );
    }

    // 加载更多历史
    if (widget.isLoadingMoreHistory != oldWidget.isLoadingMoreHistory) {
      _evalJs(
        'ChatBridge.setLoadingMore(${widget.isLoadingMoreHistory})',
      );
    }
  }

  /// 首次 WebView 就绪时，全量同步状态。
  void _syncFullState() {
    _syncTheme();
    // 传递本地图片代理服务器地址
    final server = _LocalImageServer.instance;
    if (server.isRunning) {
      _evalJs(
        "ChatBridge.setImageProxyBase('http://127.0.0.1:${server.port}')",
      );
    }
    _evalJs(
      "ChatBridge.setModelInfo('${_escJs(widget.model ?? '')}', ${widget.modelSupportsVision}, ${widget.modelSupportsTools})",
    );
    _evalJs(
      'ChatBridge.setStreamingState(${widget.isStreaming}, ${widget.streamingSupported})',
    );
    _evalJs(
      'ChatBridge.setGeneratingState(${widget.isGenerating})',
    );
    if (widget.systemPrompt.isNotEmpty) {
      _evalJs(
        "ChatBridge.setSystemPrompt('${_escJs(widget.systemPrompt)}')",
      );
    }
    if (widget.attachments.isNotEmpty) {
      _evalJs(
        "ChatBridge.setAttachments('${_escJs(jsonEncode(widget.attachments))}')",
      );
    }
    // 加载全部消息
    _syncMessagesFullLoad();
  }

  /// 全量加载消息到 WebView。
  void _syncMessagesFullLoad() {
    final jsonList = widget.messages.map((m) => _messageToJson(m)).toList();
    final encoded = jsonEncode(jsonList);
    _evalJs("ChatBridge.loadMessages('${_escJs(encoded)}', false)");
    _syncedMessageIds = widget.messages.map((m) => m.isarId).toList();
    _syncedContentLengths.clear();
    _syncedReasoningLengths.clear();
    _syncedToolLogCounts.clear();
    for (final m in widget.messages) {
      _syncedContentLengths[m.isarId] = m.content.length;
      _syncedReasoningLengths[m.isarId] = (m.reasoning ?? '').length;
      _syncedToolLogCounts[m.isarId] =
          widget.toolLogsForMessage(m.isarId).length;
    }
  }

  /// 增量同步消息变化。
  void _syncMessages() {
    final currentIds = widget.messages.map((m) => m.isarId).toList();

    // 检测是否是历史消息前插（prepend）
    if (currentIds.length > _syncedMessageIds.length &&
        _syncedMessageIds.isNotEmpty) {
      final firstOldId = _syncedMessageIds.isNotEmpty ? _syncedMessageIds.first : -1;
      final idxInNew = currentIds.indexOf(firstOldId);
      if (idxInNew > 0) {
        // 前面插入了历史消息
        final prependMsgs =
            widget.messages.sublist(0, idxInNew).map((m) => _messageToJson(m)).toList();
        final encoded = jsonEncode(prependMsgs);
        _evalJs("ChatBridge.loadMessages('${_escJs(encoded)}', true)");
        _syncedMessageIds = currentIds;
        for (final m in widget.messages.sublist(0, idxInNew)) {
          _syncedContentLengths[m.isarId] = m.content.length;
          _syncedReasoningLengths[m.isarId] = (m.reasoning ?? '').length;
          _syncedToolLogCounts[m.isarId] =
              widget.toolLogsForMessage(m.isarId).length;
        }
        // 继续检查后续消息的更新
      }
    }

    // 检测新增消息（append）
    for (final m in widget.messages) {
      if (!_syncedMessageIds.contains(m.isarId)) {
        final json = jsonEncode(_messageToJson(m));
        _evalJs("ChatBridge.addMessage('${_escJs(json)}')");
        _syncedContentLengths[m.isarId] = m.content.length;
        _syncedReasoningLengths[m.isarId] = (m.reasoning ?? '').length;
        _syncedToolLogCounts[m.isarId] =
            widget.toolLogsForMessage(m.isarId).length;
      }
    }

    // 检测删除的消息
    for (final oldId in _syncedMessageIds) {
      if (!currentIds.contains(oldId)) {
        _evalJs('ChatBridge.deleteMessage($oldId)');
        _syncedContentLengths.remove(oldId);
        _syncedReasoningLengths.remove(oldId);
        _syncedToolLogCounts.remove(oldId);
      }
    }

    // 检测内容更新（流式场景）
    for (final m in widget.messages) {
      final oldContentLen = _syncedContentLengths[m.isarId] ?? 0;
      final oldReasoningLen = _syncedReasoningLengths[m.isarId] ?? 0;
      final oldToolCount = _syncedToolLogCounts[m.isarId] ?? 0;
      final newContentLen = m.content.length;
      final newReasoningLen = (m.reasoning ?? '').length;
      final toolLogs = widget.toolLogsForMessage(m.isarId);
      final newToolCount = toolLogs.length;

      if (newContentLen != oldContentLen) {
        final rewrittenContent = _rewriteLocalImageUrlsInContent(
          m.content,
          _LocalImageServer.instance,
        );
        _evalJs(
          "ChatBridge.updateMessageContent(${m.isarId}, '${_escJs(rewrittenContent)}')",
        );
        _syncedContentLengths[m.isarId] = newContentLen;
      }

      if (newReasoningLen != oldReasoningLen) {
        _evalJs(
          "ChatBridge.updateThinkingContent(${m.isarId}, '${_escJs(m.reasoning ?? '')}', ${m.reasoningTimeMs ?? 0})",
        );
        _syncedReasoningLengths[m.isarId] = newReasoningLen;
      }

      if (newToolCount > oldToolCount) {
        for (int i = oldToolCount; i < newToolCount; i++) {
          final logJson = jsonEncode(toolLogs[i].toJson());
          _evalJs(
            "ChatBridge.addToolLog(${m.isarId}, '${_escJs(logJson)}')",
          );
        }
        _syncedToolLogCounts[m.isarId] = newToolCount;
      }

      // 更精确：如果之前在流式中，现在不在了
      if (!widget.isMessageStreaming(m.isarId) && m.role == 'assistant') {
        final canContinue = widget.canContinueAssistantMessage(m.isarId);
        _evalJs(
          'ChatBridge.endStreaming(${m.isarId}, $canContinue)',
        );
      }
    }

    _syncedMessageIds = currentIds;
  }

  /// 同步主题色到 WebView。
  void _syncTheme() {
    final cs = Theme.of(context).colorScheme;
    final colors = {
      'bg': _colorToHex(cs.surface),
      'on-surface': _colorToHex(cs.onSurface),
      'on-surface-variant': _colorToHex(cs.onSurfaceVariant),
      'surface-container': _colorToHex(cs.surfaceContainer),
      'surface-container-high': _colorToHex(cs.surfaceContainerHigh),
      'surface-container-highest': _colorToHex(cs.surfaceContainerHighest),
      'primary': _colorToHex(cs.primary),
      'on-primary': _colorToHex(cs.onPrimary),
      'primary-container': _colorToHex(cs.primaryContainer),
      'on-primary-container': _colorToHex(cs.onPrimaryContainer),
      'secondary-container': _colorToHex(cs.secondaryContainer),
      'on-secondary-container': _colorToHex(cs.onSecondaryContainer),
      'outline': _colorToHex(cs.outline),
      'outline-variant': _colorToHex(cs.outlineVariant),
      'error': _colorToHex(cs.error),
      'code-bg': _colorToHex(cs.surfaceContainerLow),
    };
    _evalJs("ChatBridge.setTheme('${_escJs(jsonEncode(colors))}')");
  }

  /// 将 Message 转为 JS 侧需要的 JSON 结构。
  Map<String, dynamic> _messageToJson(Message m) {
    final isLast = widget.messages.isNotEmpty &&
        widget.messages.last.isarId == m.isarId;
    final toolLogs = widget.toolLogsForMessage(m.isarId);
    final server = _LocalImageServer.instance;
    final rewrittenContent = _rewriteLocalImageUrlsInContent(m.content, server);

    // 附件中的本地图片路径统一转为代理 URL，避免 WebView 直接访问 file 路径失败。
    final rawPaths = m.imagePaths ?? [];
    final resolvedPaths = rawPaths.map((path) {
      return _toProxyImageUrl(path, server);
    }).toList();

    return {
      'id': m.isarId,
      'role': m.role,
      // 正文中的 Markdown/HTML 图片 URL 也需要重写，确保本地图片可见。
      'content': rewrittenContent,
      'reasoning': m.reasoning ?? '',
      'reasoningTimeMs': m.reasoningTimeMs ?? 0,
      'imagePaths': resolvedPaths,
      'isStreaming': widget.isMessageStreaming(m.isarId),
      'isLast': isLast,
      'canContinue': isLast && m.role == 'assistant'
          ? widget.canContinueAssistantMessage(m.isarId)
          : false,
      'toolLogs': toolLogs.map((l) => l.toJson()).toList(),
    };
  }

  static bool _isImageFile(String path) {
    final ext = p.extension(path.split('?').first.split('#').first).toLowerCase();
    return {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.heic', '.heif'}
        .contains(ext);
  }

  /// 匹配 Markdown 图片语法：![alt](url "title")
  static final RegExp _markdownImagePattern = RegExp(
    r'!\[([^\]]*)\]\(\s*(<[^>]+>|[^)\s]+)([^)]*)\)',
    multiLine: true,
  );

  /// 匹配 HTML 图片标签中带引号的 src 属性。
  static final RegExp _htmlImgSrcQuotedPattern = RegExp(
    r"""(<img\b[^>]*\bsrc\s*=\s*)(["'])([^"']+)(\2)""",
    caseSensitive: false,
    multiLine: true,
  );

  /// 匹配 HTML 图片标签中不带引号的 src 属性。
  static final RegExp _htmlImgSrcUnquotedPattern = RegExp(
    r"""(<img\b[^>]*\bsrc\s*=\s*)([^"'\s>]+)""",
    caseSensitive: false,
    multiLine: true,
  );

  /// 重写消息正文里的本地图片路径（Markdown + HTML img）。
  static String _rewriteLocalImageUrlsInContent(
    String content,
    _LocalImageServer server,
  ) {
    if (content.isEmpty || !server.isRunning) return content;

    var rewritten = content.replaceAllMapped(_markdownImagePattern, (match) {
      final alt = match.group(1) ?? '';
      final urlToken = match.group(2) ?? '';
      final tail = match.group(3) ?? '';
      final rawUrl = _stripAngleBrackets(urlToken.trim());
      final proxied = _toProxyImageUrl(rawUrl, server);
      if (proxied == rawUrl) {
        return match.group(0) ?? '';
      }
      final wrappedUrl = urlToken.trim().startsWith('<') && urlToken.trim().endsWith('>')
          ? '<$proxied>'
          : proxied;
      return '![$alt]($wrappedUrl$tail)';
    });

    rewritten = rewritten.replaceAllMapped(_htmlImgSrcQuotedPattern, (match) {
      final prefix = match.group(1) ?? '';
      final quote = match.group(2) ?? '"';
      final src = match.group(3) ?? '';
      final proxied = _toProxyImageUrl(src, server);
      return '$prefix$quote$proxied$quote';
    });

    rewritten = rewritten.replaceAllMapped(_htmlImgSrcUnquotedPattern, (match) {
      final prefix = match.group(1) ?? '';
      final src = match.group(2) ?? '';
      final proxied = _toProxyImageUrl(src, server);
      return '$prefix$proxied';
    });

    return rewritten;
  }

  /// 将本地路径转换为 WebView 可访问的 localhost 代理 URL。
  static String _toProxyImageUrl(String rawPath, _LocalImageServer server) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) return rawPath;

    // 远程 URL 或 data URI 保持不变。
    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('data:')) {
      return rawPath;
    }

    final normalized = _normalizeLocalPath(trimmed);
    if (!_isLocalImagePath(normalized) || !server.isRunning) {
      return rawPath;
    }
    return server.proxyUrl(normalized);
  }

  /// 统一规整 file URI 与编码路径，避免同一路径因格式差异导致匹配失败。
  static String _normalizeLocalPath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.startsWith('file://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null && uri.scheme == 'file') {
        try {
          return uri.toFilePath(windows: Platform.isWindows);
        } catch (_) {
          // 保持回退语义，尽量不破坏原始内容。
        }
      }
    }
    try {
      return Uri.decodeFull(trimmed);
    } catch (_) {
      return trimmed;
    }
  }

  /// 判断路径是否为“本地绝对图片路径”。
  static bool _isLocalImagePath(String path) {
    final normalized = path.split('?').first.split('#').first;
    final isAndroidAbs = normalized.startsWith('/data/') ||
        normalized.startsWith('/storage/') ||
        normalized.startsWith('/sdcard/');
    final isWindowsAbs = RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(normalized);
    return (isAndroidAbs || isWindowsAbs) && _isImageFile(normalized);
  }

  static String _stripAngleBrackets(String value) {
    if (value.startsWith('<') && value.endsWith('>') && value.length > 1) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }

  // ===== 工具方法 =====

  void _evalJs(String js) {
    _controller.runJavaScript(js);
  }

  static String _escJs(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }

  static String _colorToHex(Color c) {
    return '#${c.red.toRadixString(16).padLeft(2, '0')}'
        '${c.green.toRadixString(16).padLeft(2, '0')}'
        '${c.blue.toRadixString(16).padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
