import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:now_chat/app/router.dart';
import 'package:now_chat/ui/widgets/chat_list_item.dart';
import 'package:provider/provider.dart';

import '../../providers/chat_provider.dart';


/// ChatListPage 页面。
class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

/// _ChatListPageState 视图状态。
class _ChatListPageState extends State<ChatListPage> {
  bool _isSelecting = false;
  /// 多选模式下的会话 ID 集合。
  final Set<int> _selectedIds = {};

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final chats = chatProvider.chatList;
    final color = Theme.of(context).colorScheme;

    return PopScope(
      // 多选时优先退出选择态，不直接退出页面。
      canPop: !_isSelecting,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop && _isSelecting) {
          // 退出多选模式
          setState(() {
            _isSelecting = false;
            _selectedIds.clear();
          });
        } else if (!didPop && !_isSelecting) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: color.surface,
          title: Text(
            _isSelecting
                ? "已选择 ${_selectedIds.length} 项"
                : "会话",
            style: TextStyle(color: color.onSurface),
          ),
          actions: [
            if (_isSelecting)
              IconButton(
                icon: Icon(Icons.delete_outline,
                    color: _selectedIds.isEmpty
                        ? color.onSurfaceVariant.withAlpha(120)
                        : color.error),
                onPressed: _selectedIds.isEmpty
                    ? null
                    : () async {
                        final confirm = await _confirmDelete(context);
                        if (confirm == true) {
                          for (final id in _selectedIds) {
                            chatProvider.deleteChat(id);
                          }
                          setState(() {
                            _isSelecting = false;
                            _selectedIds.clear();
                          });
                        }
                      },
              ),
          ],
          leading: _isSelecting
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _isSelecting = false;
                      _selectedIds.clear();
                    });
                  },
                )
              : null,
        ),
      
        floatingActionButton: !_isSelecting
            ? FloatingActionButton(
                onPressed: () async {
                  Navigator.pushNamed(
                    context,
                    AppRoutes.chatDetail,
                  );
                },
                tooltip: "新建会话",
                child: const Icon(Icons.edit_outlined),
              )
            : null,
        body: chats.isEmpty
        ? Center(
            child: Text(
              '暂无会话',
              style: TextStyle(fontSize: 16, color: color.onSurfaceVariant),
            ),
          )
        : ListView.separated(
            itemCount: chats.length,
            separatorBuilder: (_, __) =>
                Divider(height: 2, thickness: 2, color: color.inversePrimary.withAlpha(80)),
            itemBuilder: (context, index) {
              final chat = chats[index];
  
              return ChatListItem(
                chat: chat,
                isSelected: _selectedIds.contains(chat.id),
                isSelecting: _isSelecting,
                onTap: () {
                  if (_isSelecting) {
                    setState(() {
                      if (_selectedIds.contains(chat.id)) {
                        _selectedIds.remove(chat.id);
                      } else {
                        _selectedIds.add(chat.id);
                      }
                    });
                  } else {
                    // 普通模式：进入会话详情。
                    Navigator.pushNamed(context, AppRoutes.chatDetail,
                        arguments: {"chatId": chat.id});
                  }
                },
                onLongPress: () {
                  setState(() {
                    _isSelecting = true;
                    _selectedIds.add(chat.id);
                  });
                },
              );
            },
          ),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) async {
    final color = Theme.of(context).colorScheme;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: color.surfaceContainerLow,
        title: Text('确认删除？', style: TextStyle(color: color.onSurface)),
        content: Text('是否删除所选的${_selectedIds.length}项会话，删除后将无法恢复。',
            style: TextStyle(color: color.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(color: color.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('删除', style: TextStyle(color: color.error)),
          ),
        ],
      ),
    );
  }
}
