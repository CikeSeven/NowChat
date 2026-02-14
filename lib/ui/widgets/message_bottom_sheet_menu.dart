import 'package:flutter/material.dart';

import '../../core/models/message.dart';


Future<void> showModalBottomSheetMenu({
  required BuildContext context,
  required List<SheetMenuItem> items,
  required Message message,
}){
  final isAssitant = message.role == 'assistant';
  final color = Theme.of(context).colorScheme;
  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: color.surfaceContainerHigh,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24))
    ),
    builder: (context) {
      if (isAssitant) return _AssistantMenuSheet(items: items, message: message);
      return _buildUserMenu(context: context, items: items, message: message);
    },
  );

}

// 用户菜单
Widget _buildUserMenu ({
  required BuildContext context,
  required List<SheetMenuItem> items,
  required Message message,
}) {
  final color = Theme.of(context).colorScheme;

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        //顶部拖拽条
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(bottom: 3),
          decoration: BoxDecoration(
            color: color.outlineVariant,
            borderRadius: BorderRadius.circular(2)
          ),
        ),

        //菜单项
        ...items.map((item) {
          return ListTile(
            leading: item.icon,
            title: Text(item.label,
              style: TextStyle(color: color.onSurface),),
              onTap: () {
                Navigator.pop(context);
                item.onTap?.call();
              },
          );
        })
      ],
    ),
  );
}


// AI消息菜单
class _AssistantMenuSheet extends StatefulWidget {
  final List<SheetMenuItem> items;
  final Message message;
  const _AssistantMenuSheet({required this.items, required this.message});

  @override
  State<_AssistantMenuSheet> createState() => _AssistantMenuSheetState();
}

class _AssistantMenuSheetState extends State<_AssistantMenuSheet> {
  final controller = DraggableScrollableController();
  double sheetSize = 0.5;

  @override
  void initState() {
    super.initState();
    controller.addListener(() {
      setState(() {
        sheetSize = controller.size;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isFullScreen = sheetSize > 0.8;
    final visibleItems = isFullScreen ? widget.items.take(2).toList() : widget.items;
    final color = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
        controller: controller,
        expand: false,
        initialChildSize: 0.5, // 初始高度
        minChildSize: 0.5,     // 最小高度
        maxChildSize: 1.0,     // 最大高度全屏
        snapSizes: const [0.5, 1.0],
        snap: true,
        builder: (context, scrollController){
          return SingleChildScrollView(
            controller: scrollController,
            child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                //顶部拖拽条
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 3),
                  decoration: BoxDecoration(
                    color: color.outlineVariant,
                    borderRadius: BorderRadius.circular(2)
                  ),
                ),
        
                //菜单项
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...visibleItems.map((item) {
                        return ListTile(
                          leading:item.icon,
                          title: Text(item.label,
                              style: TextStyle(color: color.onSurface)),
                          onTap: () {
                            Navigator.pop(context);
                            item.onTap?.call();
                          },
                        );
                      }),
                    ]
                  )
                ),

                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Divider(),
                ),
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SelectableText(
                          widget.message.content
                        ),
                      ),
                    ],
                  )
              ],
            ),
          ),
          );
        } 
      );
  }
}



/// 底部菜单项数据模型
class SheetMenuItem {
  final Icon icon;
  final String label;
  final VoidCallback? onTap;

  const SheetMenuItem({
    required this.icon,
    required this.label,
    this.onTap,
  });
}
