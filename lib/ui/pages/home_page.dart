import 'package:flutter/material.dart';
import 'package:now_chat/ui/pages/workbench_page.dart';
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
  final GlobalKey<WorkbenchPageState> _workbenchPageKey =
      GlobalKey<WorkbenchPageState>();

  /// 首页一级页面缓存，使用 BottomNavigationBar 切换。
  late final List<Widget> _pages = [
    const ChatListPage(),
    WorkbenchPage(key: _workbenchPageKey),
    const ApiPage(),
    const SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return WillPopScope(
      // 根页面返回策略：
      // - 非会话页：先切回会话页，不直接退出应用。
      // - 会话页：按系统默认行为退出应用。
      onWillPop: () async {
        if (_index != 0) {
          // 工作台生图页可能存在“内部可取消状态”（例如已选原图、多选态），
          // 这种情况优先由工作台消费返回，不直接切换到会话页。
          if (_index == 1 &&
              (_workbenchPageKey.currentState?.consumeBackAction() ?? false)) {
            return false;
          }
          setState(() => _index = 0);
          return false;
        }
        return true;
      },
      child: Scaffold(
        // 使用 IndexedStack 保活一级页面状态，避免工作台子页切换后回到默认页签。
        body: IndexedStack(
          index: _index,
          // IndexedStack 会同时保活多个页面。
          // 这里仅允许当前页面参与 Hero，避免多个页面中的默认 FAB heroTag 冲突。
          children: List<Widget>.generate(_pages.length, (i) {
            return HeroMode(enabled: i == _index, child: _pages[i]);
          }),
        ),
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
              label: '工作台',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.api), label: 'API'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: '设置'),
          ],
        ),
      ),
    );
  }
}
