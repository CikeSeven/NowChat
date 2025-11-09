
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart';
import 'package:now_chat/app/router.dart';
import 'package:now_chat/core/models/message.dart';
import 'package:now_chat/ui/widgets/markdown_message_widget.dart';
import 'message_bottom_sheet_menu.dart';

class AssistantMessageWidget extends StatefulWidget {
  final Message message;
  final bool isGenerating;
  final VoidCallback onDelete;
  const AssistantMessageWidget({super.key, required this.message, required this.isGenerating, required this.onDelete});

  @override
  State<AssistantMessageWidget> createState() => _AssistantMessageWidgetState();
}

class _AssistantMessageWidgetState extends State<AssistantMessageWidget>
  with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
    final color = Theme.of(context).colorScheme;
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
              icon: Icon(Icons.delete_outline, color: color.error,),
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
                            color: color.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: _toggleExpand,
                          child: RotationTransition(
                            turns: Tween<double>(begin: 0, end: 0.5)
                                .animate(CurvedAnimation(
                                    parent: _controller,
                                    curve: Curves.easeInOut)),
                            child: Icon(
                              Icons.expand_more,
                              size: 22,
                              color: color.onSurfaceVariant,
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
                          color: color.surfaceContainerHighest.withAlpha(130),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          message.reasoning!,
                          style: TextStyle(
                            color: color.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      crossFadeState: _expanded
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                    ),
                  ],
                ),
              ),

            // 主内容，支持Markdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
              ),
              child: MarkdownMessageWidget(data: message.content),
            ),

            // 底部按钮
            if (!widget.isGenerating)
            Row(
              children: [
                // 重新生成按钮
                IconButton(
                  onPressed: () {},
                  icon: Icon(
                    size: 20,
                    Icons.refresh_outlined
                  ),
                  tooltip: "重新生成",
                ),
                Spacer(),

                // 编辑按钮
                IconButton(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      AppRoutes.editMessage,
                      arguments: message,
                    );
                  },
                  icon: Icon(
                    size: 20,
                    Icons.edit_outlined
                  ),
                  tooltip: "编辑",
                ),

                //复制按钮
                IconButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: message.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('内容已复制')),
                    );
                  },
                  icon: Icon(
                    size: 20,
                    Icons.copy_outlined
                  ),
                  tooltip: "复制",
                )
              ],
            ),
          ],
        ),
      ),
    );
  }
}