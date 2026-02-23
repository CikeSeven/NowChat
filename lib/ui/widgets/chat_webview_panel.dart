import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:now_chat/core/models/chat_session.dart';
import 'package:now_chat/core/models/message.dart';
import 'package:now_chat/core/models/tool_execution_log.dart';
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';

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
          final act = data['action'] as String? ?? '';
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
  Future<void> _syncMessagesFullLoad() async {
    final jsonList = await Future.wait(
      widget.messages.map((m) => _messageToJson(m)),
    );
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
  Future<void> _syncMessages() async {
    final currentIds = widget.messages.map((m) => m.isarId).toList();

    // 检测是否是历史消息前插（prepend）
    if (currentIds.length > _syncedMessageIds.length &&
        _syncedMessageIds.isNotEmpty) {
      final firstOldId = _syncedMessageIds.isNotEmpty ? _syncedMessageIds.first : -1;
      final idxInNew = currentIds.indexOf(firstOldId);
      if (idxInNew > 0) {
        // 前面插入了历史消息
        final prependMsgs = await Future.wait(
          widget.messages.sublist(0, idxInNew).map((m) => _messageToJson(m)),
        );
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
        final msgJson = await _messageToJson(m);
        final json = jsonEncode(msgJson);
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
        _evalJs(
          "ChatBridge.updateMessageContent(${m.isarId}, '${_escJs(m.content)}')",
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

      // 检测流式结束
      final wasStreaming = _syncedMessageIds.contains(m.isarId) &&
          widget.isMessageStreaming(m.isarId) == false &&
          oldContentLen > 0;
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
  Future<Map<String, dynamic>> _messageToJson(Message m) async {
    final isLast = widget.messages.isNotEmpty &&
        widget.messages.last.isarId == m.isarId;
    final toolLogs = widget.toolLogsForMessage(m.isarId);

    // 将本地图片路径转为 base64 data URI
    final rawPaths = m.imagePaths ?? [];
    final resolvedPaths = <String>[];
    for (final path in rawPaths) {
      final dataUri = await _imagePathToDataUri(path);
      resolvedPaths.add(dataUri ?? path);
    }

    return {
      'id': m.isarId,
      'role': m.role,
      'content': m.content,
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

  /// 将本地图片文件路径转为 base64 data URI。
  Future<String?> _imagePathToDataUri(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
      final mimeMap = {
        'png': 'image/png',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'gif': 'image/gif',
        'webp': 'image/webp',
        'bmp': 'image/bmp',
        'heic': 'image/heic',
        'heif': 'image/heif',
      };
      final mime = mimeMap[ext] ?? 'image/png';
      return 'data:$mime;base64,${base64Encode(bytes)}';
    } catch (e) {
      debugPrint('ChatWebViewPanel: _imagePathToDataUri error: $e');
      return null;
    }
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
