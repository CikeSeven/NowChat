import 'package:flutter/material.dart';
import 'package:now_chat/providers/agent_provider.dart';
import 'package:now_chat/ui/widgets/markdown_message_widget.dart';

/// 智能体一次性对话结果面板。
class AgentOneShotResultCard extends StatelessWidget {
  final bool isGenerating;
  final String streamingContent;
  final String streamingReasoning;
  final AgentOneShotResult? result;
  final VoidCallback onClear;

  const AgentOneShotResultCard({
    super.key,
    required this.isGenerating,
    required this.streamingContent,
    required this.streamingReasoning,
    required this.result,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    // 生成中展示流式缓存，结束后展示结果快照。
    final activeContent = isGenerating ? streamingContent : (result?.content ?? '');
    final activeReasoning =
        isGenerating ? streamingReasoning : (result?.reasoning ?? '');
    final hasContent = activeContent.trim().isNotEmpty;
    final hasReasoning = activeReasoning.trim().isNotEmpty;
    final error = result?.error;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '本次回复',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: color.onSurface,
                  ),
                ),
                const Spacer(),
                if (!isGenerating && result != null)
                  IconButton(
                    tooltip: '清空',
                    onPressed: onClear,
                    icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                  ),
              ],
            ),
            if (isGenerating && !hasContent)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 2),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '正在生成...',
                      style: TextStyle(fontSize: 13, color: color.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            if (error != null && error.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  error,
                  style: TextStyle(fontSize: 13, color: color.error),
                ),
              ),
            if (!isGenerating && result?.interrupted == true)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '已中断本次生成',
                  style: TextStyle(fontSize: 13, color: color.onSurfaceVariant),
                ),
              ),
            if (hasReasoning) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: color.secondaryContainer.withAlpha(90),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  activeReasoning,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: color.onSecondaryContainer,
                  ),
                ),
              ),
            ],
            if (hasContent) ...[
              const SizedBox(height: 10),
              MarkdownMessageWidget(data: activeContent),
            ],
          ],
        ),
      ),
    );
  }
}
