import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';

/// README 预览使用的本地图片代理服务器。
///
/// 作用：
/// - 将本地绝对文件路径代理为 `http://127.0.0.1:<port>/local-image?...`
/// - 让 WebView 在 Android 上稳定读取本地图片文件。
class _ReadmeLocalImageServer {
  static _ReadmeLocalImageServer? _instance;
  HttpServer? _server;

  _ReadmeLocalImageServer._();

  static _ReadmeLocalImageServer get instance {
    _instance ??= _ReadmeLocalImageServer._();
    return _instance!;
  }

  bool get isRunning => _server != null;
  int get port => _server?.port ?? 0;

  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleRequest);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.uri.path != '/local-image') {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found');
        await request.response.close();
        return;
      }

      final rawPath = request.uri.queryParameters['path'];
      if (rawPath == null || rawPath.trim().isEmpty) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('Missing path');
        await request.response.close();
        return;
      }

      final filePath = _normalizeIncomingPath(rawPath);
      final file = File(filePath);
      if (!await file.exists()) {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('File not found');
        await request.response.close();
        return;
      }

      final ext = p.extension(filePath).toLowerCase().replaceFirst('.', '');
      const mimeMap = <String, String>{
        'png': 'image/png',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'gif': 'image/gif',
        'webp': 'image/webp',
        'bmp': 'image/bmp',
        'heic': 'image/heic',
        'heif': 'image/heif',
        'svg': 'image/svg+xml',
      };
      final mime = mimeMap[ext] ?? 'application/octet-stream';

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.parse(mime)
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..headers.set('Access-Control-Allow-Origin', '*');
      await request.response.addStream(file.openRead());
      await request.response.close();
    } catch (e) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write('Error: $e');
      await request.response.close();
    }
  }

  String _normalizeIncomingPath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.startsWith('file://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null && uri.scheme == 'file') {
        try {
          return uri.toFilePath(windows: Platform.isWindows);
        } catch (_) {
          // 回退原路径，保持容错。
        }
      }
    }
    try {
      return Uri.decodeFull(trimmed);
    } catch (_) {
      return trimmed;
    }
  }
}

/// 插件 README WebView 预览组件。
///
/// 设计约束：
/// - README 仅做只读预览，不包含聊天输入区。
/// - Markdown 渲染样式复用聊天页面正文风格。
/// - 链接与图片点击回调上抛 Flutter 处理。
class PluginReadmeWebViewPanel extends StatefulWidget {
  final String content;
  final String? repoUrl;
  final String? localReadmePath;
  final ValueChanged<String> onLinkTap;
  final ValueChanged<String> onImageTap;

  const PluginReadmeWebViewPanel({
    super.key,
    required this.content,
    required this.repoUrl,
    required this.localReadmePath,
    required this.onLinkTap,
    required this.onImageTap,
  });

  @override
  State<PluginReadmeWebViewPanel> createState() => _PluginReadmeWebViewPanelState();
}

class _PluginReadmeWebViewPanelState extends State<PluginReadmeWebViewPanel> {
  late final WebViewController _controller;
  bool _webViewReady = false;
  bool _htmlLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: _handleJsMessage,
      );
    _ReadmeLocalImageServer.instance.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_webViewReady || _htmlLoading) return;
    _htmlLoading = true;
    _controller.setBackgroundColor(Theme.of(context).colorScheme.surface);
    _loadHtmlFromAssets();
  }

  @override
  void didUpdateWidget(covariant PluginReadmeWebViewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_webViewReady) return;
    if (widget.content != oldWidget.content) {
      _syncReadmeContent();
    }
    if (widget.repoUrl != oldWidget.repoUrl ||
        widget.localReadmePath != oldWidget.localReadmePath) {
      _syncReadmeContext();
      _syncReadmeContent();
    }
  }

  Future<void> _loadHtmlFromAssets() async {
    await _ReadmeLocalImageServer.instance.start();

    final html = await rootBundle.loadString('assets/readme_webview/index.html');
    final readmeJs =
        await rootBundle.loadString('assets/readme_webview/readme.js');
    // README 样式复用聊天页面样式，保证视觉一致。
    final chatCss = await rootBundle.loadString('assets/chat_webview/style.css');
    final bridgeJs = await rootBundle.loadString('assets/chat_webview/bridge.js');

    final inlinedHtml = html
        .replaceFirst('<link rel="stylesheet" href="style.css">', '<style>$chatCss</style>')
        .replaceFirst('<script src="bridge.js"></script>', '<script>$bridgeJs</script>')
        .replaceFirst('<script src="readme.js"></script>', '<script>$readmeJs</script>');

    await _controller.loadHtmlString(inlinedHtml);
  }

  void _handleJsMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final action = data['action'] as String?;
      switch (action) {
        case 'onReady':
          _webViewReady = true;
          _syncTheme();
          _syncReadmeContext();
          _syncReadmeContent();
          break;
        case 'onLinkTap':
          widget.onLinkTap((data['url'] as String? ?? '').trim());
          break;
        case 'onImageTap':
          widget.onImageTap((data['url'] as String? ?? '').trim());
          break;
      }
    } catch (_) {
      // README 预览场景不需要抛出 JS 解析错误，避免影响页面交互。
    }
  }

  void _syncTheme() {
    final cs = Theme.of(context).colorScheme;
    final colors = <String, String>{
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
      // Markdown 主题色：与 Flutter MarkdownMessageWidget 配色保持一致。
      'md-link': _colorToHex(cs.primary),
      'md-link-underline': _colorToRgba(cs.primary, 160 / 255),
      'md-codeblock-bg': _colorToRgba(cs.surfaceContainerHighest, 150 / 255),
      'md-codeblock-border': _colorToRgba(cs.outline, 70 / 255),
      'md-code-header-bg': _colorToHex(cs.surfaceContainerHigh),
      'md-inline-code-bg': _colorToRgba(cs.primaryContainer, 120 / 255),
      'md-inline-code-color': _colorToHex(cs.onPrimaryContainer),
      'md-blockquote-bg': _colorToRgba(cs.secondaryContainer, 90 / 255),
      'md-blockquote-border': _colorToHex(cs.secondary),
      'md-table-border': _colorToRgba(cs.outline, 120 / 255),
      'md-hr': _colorToRgba(cs.outlineVariant, 160 / 255),
    };
    _evalJs("ReadmeBridge.setTheme('${_escJs(jsonEncode(colors))}')");
  }

  void _syncReadmeContext() {
    final server = _ReadmeLocalImageServer.instance;
    final localDir = _resolveLocalReadmeDir(widget.localReadmePath);
    final repoRawBase = _resolveRepoRawBase(widget.repoUrl);
    final imageProxyBase = server.isRunning ? 'http://127.0.0.1:${server.port}' : '';

    _evalJs(
      "ReadmeBridge.setContext('${_escJs(localDir)}','${_escJs(repoRawBase)}','${_escJs(imageProxyBase)}')",
    );
  }

  void _syncReadmeContent() {
    _evalJs("ReadmeBridge.setReadme('${_escJs(widget.content)}')");
  }

  String _resolveLocalReadmeDir(String? readmePath) {
    final normalized = (readmePath ?? '').trim();
    if (normalized.isEmpty) return '';
    return p.dirname(normalized);
  }

  String _resolveRepoRawBase(String? repoUrl) {
    final normalized = (repoUrl ?? '').trim();
    if (normalized.isEmpty) return '';
    final uri = Uri.tryParse(normalized);
    if (uri == null) return '';
    final segments = uri.pathSegments.where((item) => item.trim().isNotEmpty).toList();
    if (segments.length < 2) return '';
    final owner = segments[0];
    final repo = segments[1].replaceAll('.git', '');
    if (owner.isEmpty || repo.isEmpty) return '';
    return 'https://raw.githubusercontent.com/$owner/$repo/HEAD/';
  }

  void _evalJs(String script) {
    _controller.runJavaScript(script);
  }

  String _escJs(String input) {
    return input
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }

  String _colorToHex(Color c) {
    return '#${c.red.toRadixString(16).padLeft(2, '0')}'
        '${c.green.toRadixString(16).padLeft(2, '0')}'
        '${c.blue.toRadixString(16).padLeft(2, '0')}';
  }

  /// 将 Flutter Color 转为 CSS rgba 字符串（保留透明度）。
  String _colorToRgba(Color c, double opacity) {
    final clamped = opacity.clamp(0.0, 1.0);
    return 'rgba(${c.red}, ${c.green}, ${c.blue}, ${clamped.toStringAsFixed(3)})';
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
