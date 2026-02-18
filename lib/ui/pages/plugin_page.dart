import 'package:flutter/material.dart';
import 'package:now_chat/providers/python_plugin_provider.dart';
import 'package:now_chat/ui/pages/python_plugin_detail_page.dart';
import 'package:provider/provider.dart';

/// 插件中心首页：当前仅提供 Python 插件入口。
class PluginPage extends StatelessWidget {
  const PluginPage({super.key});

  Color _stateColor(BuildContext context, PythonPluginInstallState state) {
    final color = Theme.of(context).colorScheme;
    switch (state) {
      case PythonPluginInstallState.notInstalled:
        return color.outline;
      case PythonPluginInstallState.downloading:
      case PythonPluginInstallState.installing:
        return color.primary;
      case PythonPluginInstallState.ready:
        return Colors.green;
      case PythonPluginInstallState.broken:
        return color.error;
    }
  }

  String _stateText(PythonPluginInstallState state) {
    switch (state) {
      case PythonPluginInstallState.notInstalled:
        return '未就绪';
      case PythonPluginInstallState.downloading:
        return '下载中';
      case PythonPluginInstallState.installing:
        return '安装中';
      case PythonPluginInstallState.ready:
        return '已就绪';
      case PythonPluginInstallState.broken:
        return '异常';
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PythonPluginProvider>();
    final color = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('插件中心')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.code_rounded,
                  color: color.primary,
                  size: 20,
                ),
              ),
              title: const Text(
                'Python 插件',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '管理 Python 包并执行代码',
                  style: TextStyle(fontSize: 12.5, color: color.onSurfaceVariant),
                ),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _stateText(provider.installState),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: _stateColor(context, provider.installState),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (provider.isBusy)
                    SizedBox(
                      width: 64,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: LinearProgressIndicator(
                          value:
                              provider.downloadProgress > 0 &&
                                      provider.downloadProgress <= 1
                                  ? provider.downloadProgress
                                  : null,
                        ),
                      ),
                    ),
                ],
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PythonPluginDetailPage(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
