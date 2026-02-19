import 'package:flutter/material.dart';
import 'package:now_chat/providers/plugin_provider.dart';
import 'package:now_chat/ui/pages/plugin_detail_page.dart';
import 'package:provider/provider.dart';

/// 插件中心页：展示插件列表并支持本地 zip 导入。
class PluginPage extends StatelessWidget {
  const PluginPage({super.key});

  Color _stateColor(BuildContext context, PluginInstallState state) {
    final color = Theme.of(context).colorScheme;
    switch (state) {
      case PluginInstallState.notInstalled:
        return color.outline;
      case PluginInstallState.installing:
        return color.primary;
      case PluginInstallState.ready:
        return Colors.green;
      case PluginInstallState.broken:
        return color.error;
    }
  }

  String _stateText(PluginInstallState state) {
    switch (state) {
      case PluginInstallState.notInstalled:
        return '未安装';
      case PluginInstallState.installing:
        return '安装中';
      case PluginInstallState.ready:
        return '已就绪';
      case PluginInstallState.broken:
        return '异常';
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PluginProvider>();
    final color = Theme.of(context).colorScheme;
    final plugins = provider.plugins;

    return Scaffold(
      appBar: AppBar(
        title: const Text('插件中心'),
        actions: [
          IconButton(
            tooltip: '导入本地插件',
            onPressed: provider.isBusy ? null : provider.importLocalPlugin,
            icon: const Icon(Icons.upload_file_rounded),
          ),
          IconButton(
            tooltip: '刷新清单',
            onPressed: provider.isBusy ? null : provider.refreshManifest,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: !provider.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if ((provider.lastError ?? '').trim().isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: color.errorContainer.withAlpha(120),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      provider.lastError!,
                      style: TextStyle(
                        color: color.onErrorContainer,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                if (provider.isInstalling)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: LinearProgressIndicator(
                      value: provider.downloadProgress > 0 &&
                              provider.downloadProgress <= 1
                          ? provider.downloadProgress
                          : null,
                    ),
                  ),
                Expanded(
                  child: plugins.isEmpty
                      ? Center(
                          child: Text(
                            '暂无插件，请先刷新清单或导入本地 zip',
                            style: TextStyle(
                              color: color.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                          itemCount: plugins.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final plugin = plugins[index];
                            final state = provider.stateForPlugin(plugin.id);
                            final installed = provider.isInstalled(plugin.id);
                            final enabled = provider.isPluginEnabled(plugin.id);
                            return Card(
                              margin: EdgeInsets.zero,
                              child: ListTile(
                                contentPadding:
                                    const EdgeInsets.fromLTRB(12, 8, 10, 8),
                                title: Text(
                                  plugin.name,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    plugin.description.isEmpty
                                        ? '作者：${plugin.author}\nv${plugin.version}'
                                        : '${plugin.description}\n作者：${plugin.author} · v${plugin.version}',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: color.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                isThreeLine: true,
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      _stateText(state),
                                      style: TextStyle(
                                        color: _stateColor(context, state),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      installed
                                          ? (enabled ? '已启用' : '已禁用')
                                          : '未安装',
                                      style: TextStyle(
                                        color: color.onSurfaceVariant,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => PluginDetailPage(
                                        pluginId: plugin.id,
                                      ),
                                    ),
                                  );
                                },
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
