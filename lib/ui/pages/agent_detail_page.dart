import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:now_chat/app/router.dart';
import 'package:now_chat/core/models/agent_profile.dart';
import 'package:now_chat/core/models/ai_provider_config.dart';
import 'package:now_chat/providers/agent_provider.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:now_chat/providers/settings_provider.dart';
import 'package:now_chat/ui/widgets/markdown_message_widget.dart';
import 'package:provider/provider.dart';

/// 单个智能体详情页，负责一次性对话。
class AgentDetailPage extends StatefulWidget {
  final String agentId;

  const AgentDetailPage({super.key, required this.agentId});

  @override
  State<AgentDetailPage> createState() => _AgentDetailPageState();
}

class _AgentDetailPageState extends State<AgentDetailPage> {
  final TextEditingController _inputController = TextEditingController();
  bool _renderMarkdown = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AgentProvider>().clearLastResult();
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _deleteAgent(AgentProfile agent) async {
    final color = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            backgroundColor: color.surfaceContainerLow,
            title: Text('删除智能体', style: TextStyle(color: color.onSurface)),
            content: Text(
              '确认删除 "${agent.name}" 吗？',
              style: TextStyle(color: color.onSurfaceVariant),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(
                  '取消',
                  style: TextStyle(color: color.onSurfaceVariant),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text('删除', style: TextStyle(color: color.error)),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await context.read<AgentProvider>().deleteAgent(agent.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  _ResolvedAgentRuntime? _resolveRuntime({
    required AgentProfile agent,
    required ChatProvider chatProvider,
    required SettingsProvider settings,
  }) {
    final providerId = (agent.providerId ?? settings.defaultProviderId)?.trim();
    if (providerId == null || providerId.isEmpty) {
      return null;
    }
    final provider = chatProvider.getProviderById(providerId);
    if (provider == null) {
      return null;
    }

    final model = (agent.model ?? settings.defaultModel)?.trim();
    if (model == null || model.isEmpty || !provider.models.contains(model)) {
      return null;
    }

    final temperature = agent.temperature ?? settings.defaultTemperature;
    final topP = agent.topP ?? settings.defaultTopP;
    final maxTokens = agent.maxTokens ?? settings.defaultMaxTokens;
    final streaming = (agent.isStreaming ?? settings.defaultStreaming) &&
        provider.requestMode.supportsStreaming;

    return _ResolvedAgentRuntime(
      provider: provider,
      model: model,
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
      isStreaming: streaming,
    );
  }

  Future<void> _submitOneShot({
    required AgentProfile agent,
    required _ResolvedAgentRuntime runtime,
  }) async {
    final input = _inputController.text.trim();
    if (input.isEmpty) return;
    await context.read<AgentProvider>().runOneShot(
      AgentOneShotRequest(
        agent: agent,
        provider: runtime.provider,
        model: runtime.model,
        input: input,
        temperature: runtime.temperature,
        topP: runtime.topP,
        maxTokens: runtime.maxTokens,
        isStreaming: runtime.isStreaming,
      ),
    );
  }

  String _buildResponseText(AgentProvider provider) {
    if (provider.isGenerating) {
      return provider.streamingContent;
    }
    final result = provider.lastResult;
    if (result == null) return '';
    if ((result.error ?? '').trim().isNotEmpty) {
      return '请求失败：${result.error}';
    }
    if (result.interrupted && result.content.trim().isEmpty) {
      return '已中断，本次未产生内容。';
    }
    return result.content;
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final agentProvider = context.watch<AgentProvider>();
    final chatProvider = context.watch<ChatProvider>();
    final settings = context.watch<SettingsProvider>();
    final agent = agentProvider.getById(widget.agentId);

    if (agent == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('智能体')),
        body: const Center(child: Text('智能体不存在或已删除')),
      );
    }
    final summary = agent.summary.trim().isEmpty
        ? agent.prompt.trim()
        : agent.summary.trim();
    final runtime = _resolveRuntime(
      agent: agent,
      chatProvider: chatProvider,
      settings: settings,
    );
    final responseText = _buildResponseText(agentProvider);
    final canCopy = responseText.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              agent.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: color.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '编辑',
            onPressed: () {
              Navigator.pushNamed(
                context,
                AppRoutes.agentForm,
                arguments: {'agentId': agent.id},
              );
            },
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: () => _deleteAgent(agent),
            icon: Icon(Icons.delete_outline, color: color.error),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            MediaQuery.of(context).viewInsets.bottom + 12,
          ),
          children: [
            TextField(
              controller: _inputController,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '输入内容',
                hintText: '输入一次性任务内容',
              ),
            ),
            if (runtime == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '未找到可用模型，请在设置中配置默认模型或为该智能体绑定模型。',
                  style: TextStyle(fontSize: 12.5, color: color.error),
                ),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.center,
              child: FilledButton.icon(
                onPressed: runtime == null
                    ? null
                    : agentProvider.isGenerating
                        ? agentProvider.interruptOneShot
                        : () => _submitOneShot(
                              agent: agent,
                              runtime: runtime,
                            ),
                icon: Icon(
                  agentProvider.isGenerating
                      ? Icons.stop_circle_outlined
                      : Icons.send_rounded,
                ),
                label: Text(agentProvider.isGenerating ? '中断' : '发送'),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'AI 返回',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: color.onSurface,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: _renderMarkdown
                              ? '已开启 Markdown 渲染，点击切换为纯文本'
                              : '已关闭 Markdown 渲染，点击切换为 Markdown',
                          onPressed: () {
                            setState(() {
                              _renderMarkdown = !_renderMarkdown;
                            });
                          },
                          icon: Icon(
                            _renderMarkdown
                                ? Icons.text_snippet_outlined
                                : Icons.notes_outlined,
                            size: 18,
                            color: _renderMarkdown
                                ? color.primary
                                : color.onSurfaceVariant,
                          ),
                        ),
                        IconButton(
                          tooltip: '复制',
                          onPressed: canCopy
                              ? () {
                                  Clipboard.setData(
                                    ClipboardData(text: responseText),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('已复制')),
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.copy_rounded, size: 18),
                        ),
                      ],
                    ),
                    Divider(color: color.outlineVariant.withAlpha(120)),
                    const SizedBox(height: 6),
                    Builder(
                      builder: (context) {
                        final placeholder = responseText.trim().isEmpty;
                        if (placeholder) {
                          return Text(
                            agentProvider.isGenerating ? '正在生成...' : '暂无返回内容',
                            style: TextStyle(
                              fontSize: 14.5,
                              height: 1.5,
                              color: color.onSurfaceVariant,
                            ),
                          );
                        }
                        if (_renderMarkdown) {
                          return MarkdownMessageWidget(
                            data: responseText,
                            selectable: true,
                          );
                        }
                        return SelectionArea(
                          child: Text(
                            responseText,
                            style: TextStyle(
                              fontSize: 14.5,
                              height: 1.5,
                              color: color.onSurface,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResolvedAgentRuntime {
  final AIProviderConfig provider;
  final String model;
  final double temperature;
  final double topP;
  final int maxTokens;
  final bool isStreaming;

  const _ResolvedAgentRuntime({
    required this.provider,
    required this.model,
    required this.temperature,
    required this.topP,
    required this.maxTokens,
    required this.isStreaming,
  });
}
