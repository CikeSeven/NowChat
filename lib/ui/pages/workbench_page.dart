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
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              floating: true,
              snap: true,
              pinned: false,
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
                if (_tabController.index == 1)
                  PopupMenuButton<int>(
                    tooltip: '列表布局',
                    icon: const Icon(Icons.view_list_rounded),
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
              bottom: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.handyman_outlined), text: '工具'),
                  Tab(icon: Icon(Icons.image_outlined), text: '生图'),
                ],
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
            ),
          ],
        ),
      ),
    );
  }
}
