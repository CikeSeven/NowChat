
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:now_chat/core/models/message.dart';
import 'package:now_chat/ui/widgets/message_bottom_sheet_menu.dart';

class UserMessageWidget extends StatelessWidget {
  final Message message;
  const UserMessageWidget({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(left: 26, right: 6, top: 10, bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: color.secondaryContainer,
          borderRadius: const BorderRadius.only(
            topLeft:  Radius.circular(10),
            topRight:  Radius.circular(2),
            bottomLeft:  Radius.circular(10),
            bottomRight:  Radius.circular(10)
          ),
          child: InkWell(
            borderRadius: const BorderRadius.only(
              topLeft:  Radius.circular(10),
              topRight:  Radius.circular(2),
              bottomLeft:  Radius.circular(10),
              bottomRight:  Radius.circular(10)
            ),
            onLongPress: () {
              showModalBottomSheetMenu(
                context: context,
                items: [
                  SheetMenuItem(
                    icon: Icons.copy,
                    label: '复制全文',
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: message.content));
                    },
                  ),
                  SheetMenuItem(
                    icon: Icons.delete_outline,
                    label: '删除消息',
                    onTap: () {
                      // TODO: 删除逻辑
                    },
                  ),
                ],
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              child: Text(
                message.content,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}