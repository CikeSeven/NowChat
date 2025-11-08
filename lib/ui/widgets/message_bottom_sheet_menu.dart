import 'package:flutter/material.dart';


Future<void> showModalBottomSheetMenu({
  required BuildContext context,
  required List<SheetMenuItem> items,
}){
  final color = Theme.of(context).colorScheme;
  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: false,
    backgroundColor: color.surfaceContainerHigh,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24))
    ),
    builder: (context) {
      return SafeArea(
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
              ...items.map((item) {
                return ListTile(
                  leading: Icon(item.icon, color: color.onSurfaceVariant,),
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
        ),
      );
    },
  );

}

/// 底部菜单项数据模型
class SheetMenuItem {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const SheetMenuItem({
    required this.icon,
    required this.label,
    this.onTap,
  });
}