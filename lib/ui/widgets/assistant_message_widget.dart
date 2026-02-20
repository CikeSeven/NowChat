import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:now_chat/app/router.dart';
import 'package:now_chat/core/models/message.dart';
import 'package:now_chat/core/models/tool_execution_log.dart';
import 'package:now_chat/ui/widgets/markdown_message_widget.dart';
import 'message_bottom_sheet_menu.dart';

/// 助手消息气泡组件，负责渲染正文、思考区、操作按钮与工具调用日志。
class AssistantMessageWidget extends StatefulWidget {
  /// 流式渲染阈值：新增行数达到阈值就刷新 Markdown 快照。
  static const int streamingSnapshotLineThreshold = 1;
  /// 流式渲染阈值：新增字符达到阈值就刷新 Markdown 快照。
  static const int streamingSnapshotCharThreshold = 120;
  /// 流式渲染阈值：即使增量较小，超过时间也强制刷新一次。
  static const Duration streamingMarkdownMaxInterval = Duration(
    milliseconds: 450,
  );

  final Message message;
  final bool isGenerating;
  final bool isStreamingMessage;
  final bool showResendButton;
  final bool showContinueButton;
  final List<ToolExecutionLog> toolLogs;
  final VoidCallback onDelete;
  final VoidCallback? onResend;
  final VoidCallback? onContinue;
  const AssistantMessageWidget({
    super.key,
    required this.message,
    required this.isGenerating,
    this.isStreamingMessage = false,
    required this.showResendButton,
    this.showContinueButton = false,
    this.toolLogs = const <ToolExecutionLog>[],
    required this.onDelete,
    this.onResend,
    this.onContinue,
  });

  @override
  State<AssistantMessageWidget> createState() => _AssistantMessageWidgetState();
}

/// 助手消息内部状态：处理思考区展开与流式渲染节流快照。
class _AssistantMessageWidgetState extends State<AssistantMessageWidget>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _controller;
  String _markdownSnapshot = '';
  int _markdownSnapshotLength = 0;
  int _markdownSnapshotLineCount = 0;
  DateTime _lastSnapshotAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _setMarkdownSnapshot(widget.message.content, force: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AssistantMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.isarId != widget.message.isarId) {
      _expanded = false;
      _controller.value = 0;
      _setMarkdownSnapshot(widget.message.content, force: true);
      return;
    }

    // 注意：Message 在 Provider 中是原地更新，同一实例会跨 rebuild 复用。
    // 不能依赖 oldWidget.message.content 与 widget.message.content 比较，
    // 需要和本地快照比较才知道内容是否增长。
    final contentChanged = widget.message.content != _markdownSnapshot;
    final streamingStateChanged =
        oldWidget.isStreamingMessage != widget.isStreamingMessage;
    if (!contentChanged && !streamingStateChanged) {
      return;
    }

    if (!widget.isStreamingMessage) {
      _setMarkdownSnapshot(widget.message.content, force: true);
      return;
    }

    final currentContent = widget.message.content;
    if (currentContent.length < _markdownSnapshotLength) {
      _setMarkdownSnapshot(currentContent, force: true);
      return;
    }

    final deltaLength = currentContent.length - _markdownSnapshotLength;
    final elapsed = DateTime.now().difference(_lastSnapshotAt);
    final currentLineCount = _lineCount(currentContent);
    final lineDelta = currentLineCount - _markdownSnapshotLineCount;
    if (lineDelta >= AssistantMessageWidget.streamingSnapshotLineThreshold ||
        deltaLength >= AssistantMessageWidget.streamingSnapshotCharThreshold ||
        elapsed >= AssistantMessageWidget.streamingMarkdownMaxInterval) {
      _setMarkdownSnapshot(currentContent, force: true);
    }
  }

  /// 统计文本行数，用于判断流式阶段是否达到刷新阈值。
  int _lineCount(String text) {
    if (text.isEmpty) return 0;
    return '\n'.allMatches(text).length + 1;
  }

  /// 在流式输出中维护 Markdown 快照，降低高频完整重渲染带来的卡顿。
  void _setMarkdownSnapshot(String content, {bool force = false}) {
    if (!force && content == _markdownSnapshot) {
      return;
    }
    final snapshot = content;
    if (mounted) {
      setState(() {
        _markdownSnapshot = snapshot;
        _markdownSnapshotLength = snapshot.length;
        _markdownSnapshotLineCount = _lineCount(snapshot);
        _lastSnapshotAt = DateTime.now();
      });
      return;
    }
    _markdownSnapshot = snapshot;
    _markdownSnapshotLength = snapshot.length;
    _markdownSnapshotLineCount = _lineCount(snapshot);
    _lastSnapshotAt = DateTime.now();
  }

  /// 展开/收起思考内容区域。
  void _toggleExpand() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final message = widget.message;
    final reasoningSeconds = (message.reasoningTimeMs ?? 0) / 1000.0;

    return InkWell(
      // 长按弹出菜单
      onLongPress: () {
        showModalBottomSheetMenu(
          context: context,
          message: message,
          items: [
            SheetMenuItem(
              icon: Icon(Icons.edit),
              label: '编辑内容',
              onTap: () {
                Navigator.pushNamed(
                  context,
                  AppRoutes.editMessage,
                  arguments: message,
                );
              },
            ),
            SheetMenuItem(
              icon: Icon(Icons.copy),
              label: '复制内容',
              onTap: () {
                Clipboard.setData(ClipboardData(text: message.content));
              },
            ),
            SheetMenuItem(
              icon: Icon(Icons.delete_outline, color: colors.error),
              label: '删除消息',
              onTap: () {
                widget.onDelete();
              },
            ),
          ],
        );
      },

      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.content.isEmpty &&
                widget.isGenerating &&
                (message.reasoning == null ? true : message.reasoning!.isEmpty))
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 25,
                      height: 25,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: colors.primary,
                      ),
                    ),
                    SizedBox(width: 16),
                    const Text("生成中...", style: TextStyle(fontSize: 16)),
                  ],
                ),
              ),

            // reasoning 信息块
            if (message.reasoning != null && message.reasoning!.isNotEmpty)
              Container(
                margin: EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '已思考 ${reasoningSeconds.toStringAsFixed(1)} 秒',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: _toggleExpand,
                          child: RotationTransition(
                            turns: Tween<double>(begin: 0, end: 0.5).animate(
                              CurvedAnimation(
                                parent: _controller,
                                curve: Curves.easeInOut,
                              ),
                            ),
                            child: Icon(
                              Icons.expand_more,
                              size: 22,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // 展开区域动画
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 200),
                      firstChild: const SizedBox.shrink(),
                      secondChild: Container(
                        margin: const EdgeInsets.only(top: 8, bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest.withAlpha(130),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          message.reasoning!,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      crossFadeState:
                          _expanded
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                    ),
                  ],
                ),
              ),

            // 主内容，支持Markdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
              child: _buildMessageBody(context, message),
            ),
            if (widget.toolLogs.isNotEmpty)
              _buildToolLogs(context, widget.toolLogs),

            // 底部按钮
            if (!widget.isGenerating)
              Row(
                children: [
                  if (widget.showResendButton)
                    IconButton(
                      onPressed: widget.onResend,
                      icon: Icon(size: 20, Icons.refresh_outlined),
                      tooltip: "重新发送",
                    ),
                  if (widget.showContinueButton)
                    TextButton.icon(
                      onPressed: widget.onContinue,
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('继续'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  const Spacer(),

                  // 编辑按钮
                  IconButton(
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        AppRoutes.editMessage,
                        arguments: message,
                      );
                    },
                    icon: Icon(size: 20, Icons.edit_outlined),
                    tooltip: "编辑",
                  ),

                  //复制按钮
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: message.content));
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('内容已复制')));
                    },
                    icon: Icon(size: 20, Icons.copy_outlined),
                    tooltip: "复制",
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// 消息正文渲染：流式阶段采用“快照 Markdown + 增量纯文本”组合。
  Widget _buildMessageBody(BuildContext context, Message message) {
    final color = Theme.of(context).colorScheme;
    if (widget.isStreamingMessage) {
      final snapshot = _markdownSnapshot;
      final tailLength = message.content.length - snapshot.length;
      final tail =
          tailLength > 0 ? message.content.substring(snapshot.length) : '';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (snapshot.isNotEmpty)
            MarkdownMessageWidget(data: snapshot),
          if (tail.isNotEmpty)
            SelectableText(
              tail,
              style: TextStyle(
                fontSize: 16,
                color: color.onSurface,
                height: 1.58,
              ),
            ),
        ],
      );
    }
    return MarkdownMessageWidget(data: message.content);
  }

  /// 渲染工具调用日志摘要，帮助用户快速定位模型的工具执行过程。
  Widget _buildToolLogs(BuildContext context, List<ToolExecutionLog> logs) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 12, right: 12, bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant.withAlpha(150)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '工具调用 ${logs.length} 次',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          ...logs.map((log) {
            final statusColor =
                log.isSuccess
                    ? Colors.green.shade600
                    : (log.isError
                        ? colors.error
                        : colors.onSurfaceVariant);
            final statusIcon =
                log.isSuccess
                    ? Icons.check_circle_outline
                    : (log.isError
                        ? Icons.error_outline
                        : Icons.do_not_disturb_on_outlined);
            final durationText =
                log.durationMs == null ? '' : ' · ${log.durationMs}ms';
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(statusIcon, size: 14, color: statusColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${log.toolName}$durationText\n${log.summary}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
