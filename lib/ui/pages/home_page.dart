import 'package:flutter/material.dart';
import 'package:now_chat/ui/pages/agent_page.dart';
import 'package:now_chat/ui/pages/api_page.dart';
import 'package:now_chat/ui/pages/chat_list_page.dart';
import 'package:now_chat/ui/pages/settings_page.dart';

/// HomePage 页面。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

/// _HomePageState 视图状态。
class _HomePageState extends State<HomePage> {
  int _index = 0;

  final List<Widget> _pages = const [
    ChatListPage(),
    AgentPage(),
    ApiPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: color.surfaceContainerLow,
        selectedItemColor: color.primary,
        unselectedItemColor: color.onSurfaceVariant,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        showUnselectedLabels: true,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: '会话'),
          BottomNavigationBarItem(
            icon: Icon(Icons.handyman_outlined),
            label: '工具',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.api), label: 'API'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
