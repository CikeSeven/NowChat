import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:now_chat/providers/settings_provider.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

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

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final currentMode = settings.themeMode;

    Future<void> _showThemeMenu(BuildContext context, Offset position) async {
      final RenderBox overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox;

      final selected = await showMenu<ThemeMode>(
        context: context,
        position: RelativeRect.fromRect(
          position & const Size(40, 40),
          Offset.zero & overlay.size,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
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
        settings.setThemeMode(selected);
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          Builder(
            builder: (context) {
              Offset tapPosition = Offset.zero;
              return InkWell(
                onTapDown: (details) {
                  tapPosition = details.globalPosition;
                },
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
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'NowChat',
                applicationVersion: '1.0.0',
                applicationLegalese: '© 2025 NowChat Team',
              );
            },
          ),
        ],
      ),
    );
  }
}
