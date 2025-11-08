import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:now_chat/core/models/chat_session.dart';
import 'package:now_chat/util/app_logger.dart';

class MessageInput extends StatefulWidget {
  final ChatSession? chat;
  final bool isStreaming;
  final String? model;
  final ValueChanged<String> onSend;
  final ValueChanged<bool?> streamingChanged;
  final VoidCallback? onModelSelected;
  final VoidCallback? onExpand;

  const MessageInput({
    super.key,
    required this.chat,
    required this.onSend,
    required this.onModelSelected,
    required this.isStreaming,
    this.onExpand,
    required this.model,
    required this.streamingChanged,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final TextEditingController _controller = TextEditingController();
  

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }


  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  bool get _canSendNow =>
    _controller.text.trim().isNotEmpty &&
    (widget.chat?.model != null || widget.model != null) && !(widget.chat != null && widget.chat!.isGenerating);

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Material(
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: color.outlineVariant.withAlpha(125),
              width: 0.8,
            ),
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 输入框
                  TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.newline,
                    maxLines: 5,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: widget.chat?.isGenerating ?? false ? '消息生成中...' : '输入消息...',
                      filled: true,
                      fillColor: color.surfaceContainerHighest.withAlpha(110),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  SizedBox(height: 6,),
                  // 底部工具栏
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center, // 垂直居中
                      children: [
                        SizedBox(
                          width: 30,
                          height: 30,
                          child: IconButton(
                            padding: EdgeInsets.zero, // 去掉内边距
                            constraints: const BoxConstraints(), // 去掉默认最小尺寸
                            icon: Icon(Icons.add_circle_outline,
                                color: color.onSurfaceVariant),
                            tooltip: '展开更多功能',
                            onPressed: widget.onExpand,
                          ),
                        ),
                        SizedBox(width: 12,),
                        Text(
                          "流式输出",
                          style: TextStyle(fontSize: 13),
                        ),
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: FittedBox(
                            fit: BoxFit.fill,
                            child: Checkbox(
                              value: widget.chat?.isStreaming ?? widget.isStreaming,
                              onChanged: widget.streamingChanged,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, // 减少点击区域
                            ),
                          ),
                        ),
                        
                        Spacer(),
                        
                        InkWell(
                          onTap: widget.onModelSelected,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            child: Row(
                              children: [
                                Text(
                                  widget.chat?.model ?? widget.model ?? "选择模型",
                                  style: TextStyle(fontSize: 13),
                                ),
                                const Icon(Icons.unfold_more, size: 20,),
                              ],
                            ),
                          ),
                        ),
                        
                        SizedBox(
                          width: 45,
                          height: 30,
                          child: IconButton(
                            onPressed: () {
                             _handleSend();
                            },
                            padding: EdgeInsets.zero, // 去掉内边距
                            constraints: const BoxConstraints(), // 去掉默认最小尺寸
                            icon: Icon(
                              Icons.send,
                              color: _canSendNow
                                  ? color.primary
                                  : color.onSurfaceVariant.withAlpha(110),
                            ),
                            tooltip: '发送消息',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
