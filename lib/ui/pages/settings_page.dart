import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../providers/settings_provider.dart';

/// SettingsPage 页面。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  /// 主题枚举转中文文案。
  String _themeModeText(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
      case ThemeMode.system:
        return '跟随系统';
    }
  }

  /// 在点击位置弹出主题选择菜单。
  Future<void> _showThemeMenu(BuildContext context, Offset position) async {
    final settings = context.read<SettingsProvider>();
    final currentMode = settings.themeMode;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    final selected = await showMenu<ThemeMode>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(
          value: ThemeMode.system,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('跟随系统'),
              if (currentMode == ThemeMode.system)
                const Icon(Icons.check, color: Colors.blue),
            ],
          ),
        ),
        PopupMenuItem(
          value: ThemeMode.light,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('浅色'),
              if (currentMode == ThemeMode.light)
                const Icon(Icons.check, color: Colors.blue),
            ],
          ),
        ),
        PopupMenuItem(
          value: ThemeMode.dark,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('深色'),
              if (currentMode == ThemeMode.dark)
                const Icon(Icons.check, color: Colors.blue),
            ],
          ),
        ),
      ],
    );

    if (selected != null) {
      await settings.setThemeMode(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final currentMode = settings.themeMode;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          Builder(
            builder: (context) {
              Offset tapPosition = Offset.zero;
              return InkWell(
                onTapDown: (details) => tapPosition = details.globalPosition,
                onTap: () => _showThemeMenu(context, tapPosition),
                splashColor: Theme.of(context).colorScheme.primary.withAlpha(25),
                highlightColor: Colors.transparent,
                child: ListTile(
                  leading: const Icon(Icons.color_lens_outlined),
                  title: const Text('主题'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _themeModeText(currentMode),
                        style: const TextStyle(fontSize: 14),
                      ),
                      const Icon(Icons.unfold_more),
                    ],
                  ),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: const Text('默认对话参数'),
            subtitle: Text(
              '设置默认会话参数信息',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.pushNamed(context, AppRoutes.defaultChatParams);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.folder_copy_outlined),
            title: const Text('应用数据管理'),
            subtitle: const Text('导入/导出会话、工具和 API 数据（不含插件）'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.pushNamed(context, AppRoutes.appDataManagement);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.extension_rounded),
            title: const Text('插件中心'),
            subtitle: const Text('安装、启用与管理插件及工具'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.pushNamed(context, AppRoutes.plugin);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.pushNamed(context, AppRoutes.about);
            },
          ),
        ],
      ),
    );
  }
}
