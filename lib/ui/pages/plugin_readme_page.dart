import 'package:flutter/material.dart';
import 'package:now_chat/core/plugin/plugin_registry.dart';
import 'package:now_chat/providers/plugin_provider.dart';
import 'package:now_chat/ui/pages/image_preview_page.dart';
import 'package:now_chat/ui/widgets/plugin_readme_webview_panel.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// 插件 README 页面：支持从本地或远端仓库加载并渲染 Markdown。
class PluginReadmePage extends StatefulWidget {
  final String pluginId;

  const PluginReadmePage({
    super.key,
    required this.pluginId,
  });

  @override
  State<PluginReadmePage> createState() => _PluginReadmePageState();
}

class _PluginReadmePageState extends State<PluginReadmePage> {
  bool _isLoading = true;
  String _content = '';
  String? _error;
  String? _localReadmePath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadReadme();
    });
  }

  /// 加载 README：优先本地已安装文件，失败时可重试。
  Future<void> _loadReadme() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final provider = context.read<PluginProvider>();
      final content = await provider.loadPluginReadme(widget.pluginId);
      final localReadmePath =
          PluginRegistry.instance.resolvePluginFilePath(
            widget.pluginId,
            'README.md',
          ) ??
          PluginRegistry.instance.resolvePluginFilePath(
            widget.pluginId,
            'readme.md',
          );
      if (!mounted) return;
      setState(() {
        _content = content;
        _localReadmePath = localReadmePath;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '读取 README 失败：$e';
      });
    }
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  /// 在系统浏览器中打开 README 链接。
  Future<void> _openReadmeLink(String rawUrl) async {
    final text = rawUrl.trim();
    if (text.isEmpty) return;
    final uri = _parseUrlToUri(text);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// 打开 README 图片预览页（本地或远程都支持）。
  void _openReadmeImagePreview(String rawUrl) {
    final uri = _parseUrlToUri(rawUrl.trim());
    if (uri == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImagePreviewPage(imageUri: uri, title: 'README 图片'),
      ),
    );
  }

  /// 将 WebView 回传 URL 解析成可用的 Uri。
  ///
  /// 兼容三类输入：
  /// - 标准网络地址（https://...）
  /// - file:// 本地地址
  /// - 本地绝对路径（/data/...）
  Uri? _parseUrlToUri(String rawUrl) {
    if (rawUrl.isEmpty) return null;
    if (rawUrl.startsWith('/')) {
      return Uri.file(rawUrl);
    }
    final parsed = Uri.tryParse(rawUrl);
    if (parsed == null) return null;
    if (parsed.hasScheme) return parsed;
    return Uri.file(rawUrl);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PluginProvider>();
    final plugin = provider.getPluginById(widget.pluginId);
    final pluginName = plugin?.name ?? widget.pluginId;
    final repoUrl = plugin?.repoUrl;
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('$pluginName README'),
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : (_error != null)
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        style: TextStyle(
                          color: color.error,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _loadReadme,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              )
              : PluginReadmeWebViewPanel(
                content: _content,
                repoUrl: repoUrl,
                localReadmePath: _localReadmePath,
                onLinkTap: _openReadmeLink,
                onImageTap: _openReadmeImagePreview,
              ),
    );
  }
}
