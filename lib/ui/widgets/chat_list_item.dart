import 'package:flutter/material.dart';
import 'package:now_chat/core/models/chat_session.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:provider/provider.dart';

import '../../core/models/message.dart';

/// 聊天会话列表项组件（支持多选高亮显示）
class ChatListItem extends StatelessWidget {
  final ChatSession chat;
  final bool isSelected; // 是否被选中
  final bool isSelecting; // 是否处于多选模式
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ChatListItem({
    super.key,
    required this.chat,
    required this.isSelected,
    required this.isSelecting,
    this.onTap,
    this.onLongPress,
  });

  String _formatTime(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    if (now.difference(time).inDays == 0) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else {
      return '${time.month}/${time.day}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final chatProvider = context.watch<ChatProvider>();

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        color: isSelected
            ? color.secondaryContainer.withAlpha(130)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (isSelecting)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: isSelected ? color.primary : color.outline,
                ),
              )
            else
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.chat_bubble_outline,
                  color: color.onSecondaryContainer,
                ),
              ),

            if (!isSelecting) const SizedBox(width: 12),

            // 右侧文本部分
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题
                  Text(
                    chat.title,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w600,
                      color: color.onSurface,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),

                  // 最后一条消息
                  FutureBuilder<Message?>(
                    future: chatProvider.getLastMessage(chat.id),
                    builder: (context, snapshot) {
                      final message = snapshot.data;
                      return Text(
                         message?.content ?? "暂无消息",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      );
                    },
                  )
                  
                ],
              ),
            ),

            const SizedBox(width: 12),

            // 时间
            Text(
              _formatTime(chat.lastUpdated),
              style: TextStyle(
                fontSize: 12,
                color: color.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
