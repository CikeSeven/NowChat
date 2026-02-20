import 'package:flutter/material.dart';
import 'package:now_chat/providers/plugin_provider.dart';
import 'package:now_chat/ui/widgets/markdown_message_widget.dart';
import 'package:provider/provider.dart';

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
      if (!mounted) return;
      setState(() {
        _content = content;
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

  @override
  Widget build(BuildContext context) {
    final plugin = context.select<PluginProvider, String>(
      (provider) =>
          provider.getPluginById(widget.pluginId)?.name ?? widget.pluginId,
    );
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('$plugin README'),
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
              : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                child: MarkdownMessageWidget(
                  data: _content,
                  selectable: true,
                ),
              ),
    );
  }
}
