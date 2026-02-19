import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:now_chat/core/models/message.dart';
import 'package:now_chat/ui/widgets/message_bottom_sheet_menu.dart';

import '../../app/router.dart';

/// UserMessageWidget 组件。
class UserMessageWidget extends StatelessWidget {
  final Message message;
  final VoidCallback onDelete;
  const UserMessageWidget({
    super.key,
    required this.message,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final attachments =
        (message.imagePaths ?? const <String>[])
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();

    return Container(
      margin: const EdgeInsets.only(left: 26, right: 6, top: 10, bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: color.secondaryContainer,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(10),
            topRight: Radius.circular(1),
            bottomLeft: Radius.circular(10),
            bottomRight: Radius.circular(10),
          ),
          child: InkWell(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(10),
              topRight: Radius.circular(1),
              bottomLeft: Radius.circular(10),
              bottomRight: Radius.circular(10),
            ),
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
                    label: '复制全文',
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: message.content));
                    },
                  ),
                  SheetMenuItem(
                    icon: Icon(Icons.delete, color: color.error),
                    label: '删除消息',
                    onTap: () {
                      onDelete();
                    },
                  ),
                ],
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.content.trim().isNotEmpty)
                    Text(
                      message.content,
                      style: TextStyle(
                        fontSize: 16,
                        color:
                            Theme.of(context).colorScheme.onSecondaryContainer,
                      ),
                    ),
                  if (attachments.isNotEmpty) ...[
                    if (message.content.trim().isNotEmpty)
                      const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children:
                          attachments
                              .map((path) => _AttachmentPreview(path: path))
                              .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// _AttachmentPreview 类型定义。
class _AttachmentPreview extends StatelessWidget {
  final String path;
  const _AttachmentPreview({required this.path});

  bool get _isImage {
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

  String get _name {
    final normalized = path.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    if (idx == -1 || idx == normalized.length - 1) return normalized;
    return normalized.substring(idx + 1);
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    if (_isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            SizedBox(
              width: 110,
              height: 110,
              child: Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder:
                    (context, error, stackTrace) => Container(
                      color: color.surface.withAlpha(120),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 20,
                        color: color.onSurfaceVariant,
                      ),
                    ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                color: Colors.black45,
                child: Text(
                  _name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.surface.withAlpha(120),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.outline.withAlpha(90)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            size: 15,
            color: color.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              _name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: color.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
