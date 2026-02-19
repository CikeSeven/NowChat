import 'dart:io';

import 'package:flutter/material.dart';
import 'package:now_chat/core/models/chat_session.dart';

/// MessageInput 类型定义。
class MessageInput extends StatefulWidget {
  final ChatSession? chat;
  final bool isStreaming;
  final bool streamingSupported;
  final bool isGenerating;
  final String? model;
  final bool modelSupportsVision;
  final bool modelSupportsTools;
  final void Function(String text, List<String> attachments) onSend;
  final VoidCallback? onStopGenerating;
  final ValueChanged<bool?> streamingChanged;
  final VoidCallback? onModelSelected;
  final VoidCallback? onPickImage;
  final VoidCallback? onPickFile;
  final ValueChanged<String>? onRemoveAttachment;
  final List<String> attachments;
  final VoidCallback? onExpand;

  const MessageInput({
    super.key,
    required this.chat,
    required this.onSend,
    this.onStopGenerating,
    required this.onModelSelected,
    required this.isStreaming,
    required this.streamingSupported,
    this.isGenerating = false,
    this.onPickImage,
    this.onPickFile,
    this.onRemoveAttachment,
    this.attachments = const <String>[],
    this.onExpand,
    required this.model,
    this.modelSupportsVision = false,
    this.modelSupportsTools = false,
    required this.streamingChanged,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

/// _MessageInputState 视图状态。
class _MessageInputState extends State<MessageInput> {
  final TextEditingController _controller = TextEditingController();

  String _middleEllipsis(String text, {int keepStart = 12, int keepEnd = 10}) {
    if (text.length <= keepStart + keepEnd + 1) return text;
    final start = text.substring(0, keepStart);
    final end = text.substring(text.length - keepEnd);
    return '$start...$end';
  }

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
    if (text.isEmpty && widget.attachments.isEmpty) return;
    widget.onSend(text, List<String>.from(widget.attachments));
    _controller.clear();
  }

  String _attachmentName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final slashIndex = normalized.lastIndexOf('/');
    if (slashIndex == -1 || slashIndex == normalized.length - 1) {
      return normalized;
    }
    return normalized.substring(slashIndex + 1);
  }

  bool _isImagePath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif');
  }

  Widget _buildAttachmentPreviewItem(BuildContext context, String path) {
    final color = Theme.of(context).colorScheme;
    final isImage = _isImagePath(path);
    final fileName = _attachmentName(path);
    if (isImage) {
      return Container(
        width: 82,
        height: 82,
        margin: const EdgeInsets.only(right: 8),
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder:
                      (context, error, stackTrace) => Container(
                        color: color.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.broken_image_outlined,
                          size: 18,
                          color: color.onSurfaceVariant,
                        ),
                      ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => widget.onRemoveAttachment?.call(path),
                  child: const SizedBox(
                    width: 20,
                    height: 20,
                    child: Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.outline.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            size: 16,
            color: color.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: color.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: () => widget.onRemoveAttachment?.call(path),
            child: Icon(Icons.close, size: 14, color: color.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Future<void> _showAttachmentActions() async {
    if (widget.onPickImage == null && widget.onPickFile == null) {
      widget.onExpand?.call();
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('上传图片'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onPickImage?.call();
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_file_outlined),
                title: const Text('上传文件'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onPickFile?.call();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  bool get _canSendNow =>
      (_controller.text.trim().isNotEmpty || widget.attachments.isNotEmpty) &&
      ((widget.chat?.model?.trim().isNotEmpty ?? false) ||
          (widget.model?.trim().isNotEmpty ?? false));

  Widget _capabilityIcon(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
  }) {
    final color = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: color.secondaryContainer.withAlpha(180),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 11, color: color.onSecondaryContainer),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final modelLabel =
        (widget.model?.trim().isNotEmpty ?? false)
            ? widget.model!.trim()
            : (widget.chat?.model?.trim().isNotEmpty ?? false)
            ? widget.chat!.model!.trim()
            : '选择模型';
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
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      hintText:
                          widget.chat?.isGenerating ?? false
                              ? '消息生成中...'
                              : '输入消息...',
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
                  if (widget.attachments.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children:
                            widget.attachments
                                .map(
                                  (path) => _buildAttachmentPreviewItem(
                                    context,
                                    path,
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                  ],
                  SizedBox(height: 6),
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
                            icon: Icon(
                              Icons.add_circle_outline,
                              color: color.onSurfaceVariant,
                            ),
                            tooltip: '展开更多功能',
                            onPressed: _showAttachmentActions,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text("流式输出", style: TextStyle(fontSize: 14)),
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: FittedBox(
                            fit: BoxFit.fill,
                            child: Checkbox(
                              value:
                                  widget.streamingSupported
                                      ? (widget.chat?.isStreaming ??
                                          widget.isStreaming)
                                      : false,
                              onChanged:
                                  widget.streamingSupported
                                      ? widget.streamingChanged
                                      : null,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap, // 减少点击区域
                            ),
                          ),
                        ),

                        Expanded(
                          child: InkWell(
                            onTap: widget.onModelSelected,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 4,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Flexible(
                                    child: Tooltip(
                                      message: modelLabel,
                                      child: Text(
                                        _middleEllipsis(modelLabel),
                                        maxLines: 1,
                                        overflow: TextOverflow.clip,
                                        textAlign: TextAlign.end,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  ),
                                  if (widget.modelSupportsVision ||
                                      widget.modelSupportsTools)
                                    const SizedBox(width: 4),
                                  if (widget.modelSupportsVision)
                                    _capabilityIcon(
                                      context,
                                      icon: Icons.visibility_outlined,
                                      tooltip: '支持视觉',
                                    ),
                                  if (widget.modelSupportsVision &&
                                      widget.modelSupportsTools)
                                    const SizedBox(width: 3),
                                  if (widget.modelSupportsTools)
                                    _capabilityIcon(
                                      context,
                                      icon: Icons.build_outlined,
                                      tooltip: '支持工具',
                                    ),
                                  const SizedBox(width: 2),
                                  const Icon(Icons.unfold_more, size: 20),
                                ],
                              ),
                            ),
                          ),
                        ),

                        SizedBox(
                          width: 45,
                          height: 30,
                          child: IconButton(
                            onPressed: () {
                              if (widget.isGenerating) {
                                widget.onStopGenerating?.call();
                                return;
                              }
                              if (_canSendNow) {
                                _handleSend();
                              }
                            },
                            padding: EdgeInsets.zero, // 去掉内边距
                            constraints: const BoxConstraints(), // 去掉默认最小尺寸
                            icon: Icon(
                              widget.isGenerating
                                  ? Icons.stop_circle_outlined
                                  : Icons.send,
                              color:
                                  widget.isGenerating
                                      ? color.error
                                      : _canSendNow
                                      ? color.primary
                                      : color.onSurfaceVariant.withAlpha(110),
                            ),
                            tooltip: widget.isGenerating ? '打断生成' : '发送消息',
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
