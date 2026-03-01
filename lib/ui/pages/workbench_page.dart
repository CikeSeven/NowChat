import 'package:flutter/material.dart';
import 'package:now_chat/app/router.dart';
import 'package:now_chat/ui/pages/agent_page.dart';
import 'package:now_chat/ui/pages/workbench_image_page.dart';

/// 工作台页面：顶部二级导航（工具/生图）。
class WorkbenchPage extends StatefulWidget {
  const WorkbenchPage({super.key});

  @override
  State<WorkbenchPage> createState() => WorkbenchPageState();
}

class WorkbenchPageState extends State<WorkbenchPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final GlobalKey<WorkbenchImagePageState> _imagePageKey =
      GlobalKey<WorkbenchImagePageState>();
  int _imageListColumns = 1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 首页返回键分发入口：
  /// 当前位于生图子页时，优先由生图页消费“取消选择”等内部返回行为。
  bool consumeBackAction() {
    if (_tabController.index != 1) return false;
    return _imagePageKey.currentState?.consumeBackAction() ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final imageState = _imagePageKey.currentState;
    final imageSelectionMode = _tabController.index == 1 &&
        (imageState?.isSelectionMode ?? false);
    return Scaffold(
      appBar: AppBar(
        title: const Text('工作台'),
        actions: [
          if (_tabController.index == 0)
            IconButton(
              tooltip: '新建工具',
              onPressed: () {
                Navigator.pushNamed(context, AppRoutes.agentForm);
              },
              icon: const Icon(Icons.add),
            ),
          if (_tabController.index == 1 && imageSelectionMode) ...[
            TextButton(
              onPressed: () {
                _imagePageKey.currentState?.clearSelectionFromToolbar();
                setState(() {});
              },
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                _imagePageKey.currentState?.selectAllFromToolbar();
                setState(() {});
              },
              child: const Text('全选'),
            ),
            TextButton(
              onPressed: () async {
                await _imagePageKey.currentState?.deleteSelectionFromToolbar();
                if (!mounted) return;
                setState(() {});
              },
              child: const Text('删除'),
            ),
          ] else if (_tabController.index == 1)
            PopupMenuButton<int>(
              tooltip: '更多',
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value != _imageListColumns) {
                  setState(() {
                    _imageListColumns = value;
                  });
                }
              },
              itemBuilder:
                  (menuContext) => [
                    PopupMenuItem(
                      value: 1,
                      child: Row(
                        children: [
                          const Expanded(child: Text('一行一张')),
                          if (_imageListColumns == 1)
                            const Icon(Icons.check, size: 18),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 2,
                      child: Row(
                        children: [
                          const Expanded(child: Text('一行两张')),
                          if (_imageListColumns == 2)
                            const Icon(Icons.check, size: 18),
                        ],
                      ),
                    ),
                  ],
            ),
        ],
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverPersistentHeader(
              floating: true,
              pinned: false,
              delegate: _WorkbenchTabBarHeaderDelegate(
                context: context,
                tabBar: TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: '工具'),
                    Tab(text: '生图'),
                  ],
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            const AgentPageBody(),
            WorkbenchImagePage(
              key: _imagePageKey,
              listColumns: _imageListColumns,
              onSelectionStateChanged: () {
                if (!mounted) return;
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 工作台页签头部：
/// 仅负责二级 Tab 导航的显隐，避免把主标题栏一起卷走。
class _WorkbenchTabBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  _WorkbenchTabBarHeaderDelegate({
    required this.context,
    required this.tabBar,
  });

  final BuildContext context;
  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final color = Theme.of(this.context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: color.surface,
        border: Border(
          bottom: BorderSide(color: color.outlineVariant),
        ),
      ),
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _WorkbenchTabBarHeaderDelegate oldDelegate) {
    return oldDelegate.tabBar != tabBar || oldDelegate.context != context;
  }
}
