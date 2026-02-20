import 'package:flutter/material.dart';
import 'package:now_chat/core/models/plugin_manifest_v2.dart';
import 'package:now_chat/core/plugin/plugin_service.dart';
import 'package:now_chat/providers/plugin_provider.dart';
import 'package:now_chat/ui/pages/plugin_detail_page.dart';
import 'package:now_chat/ui/pages/plugin_readme_page.dart';
import 'package:provider/provider.dart';

/// 插件中心页：支持“已安装 / 插件市场”切换与关键字搜索。
class PluginPage extends StatefulWidget {
  const PluginPage({super.key});

  @override
  State<PluginPage> createState() => _PluginPageState();
}

class _PluginPageState extends State<PluginPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchKeyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 根据插件安装状态返回颜色标识。
  ///
  /// 状态色用于快速识别“可用/安装中/异常”。
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

  /// 根据插件安装状态返回文案。
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

  /// 按“名称 + 描述”进行不区分大小写的搜索过滤。
  ///
  /// 搜索只作用于当前 Tab 已提供的数据源。
  List<PluginDefinition> _filterPlugins(List<PluginDefinition> source) {
    final keyword = _searchKeyword.trim().toLowerCase();
    if (keyword.isEmpty) return source;
    return source.where((plugin) {
      final name = plugin.name.toLowerCase();
      final description = plugin.description.toLowerCase();
      return name.contains(keyword) || description.contains(keyword);
    }).toList();
  }

  /// 将镜像测速结果格式化为简短文案。
  String _mirrorLatencyText(int? latencyMs) {
    if (latencyMs == null) return '不可达';
    return '${latencyMs}ms';
  }

  /// 弹出镜像切换窗口：支持预设切换与测速。
  ///
  /// 保存后会触发清单刷新，使市场列表立即应用新镜像策略。
  Future<void> _showMirrorDialog(
    BuildContext context,
    PluginProvider provider,
  ) async {
    var selectedMirrorId = provider.githubMirrorId;
    var customMirrorBaseUrl = provider.githubMirrorCustomBaseUrl;
    var isTesting = false;
    var latencies = Map<String, int?>.from(provider.mirrorProbeLatenciesMs);
    final customController = TextEditingController(text: customMirrorBaseUrl);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final color = Theme.of(dialogContext).colorScheme;
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              title: const Text('选择 GitHub 镜像'),
              content: SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...provider.githubMirrorPresets.map((preset) {
                        final isSelected = selectedMirrorId == preset.id;
                        final latency = latencies[preset.id];
                        final isCustom = preset.id == PluginService.githubMirrorCustom;
                        final subtitleText =
                            isCustom && customMirrorBaseUrl.trim().isNotEmpty
                                ? '${preset.description} · ${_mirrorLatencyText(latency)}\n当前：$customMirrorBaseUrl'
                                : '${preset.description} · ${_mirrorLatencyText(latency)}';
                        return RadioListTile<String>(
                          value: preset.id,
                          groupValue: selectedMirrorId,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            preset.name,
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            subtitleText,
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  latency == null && !isSelected
                                      ? color.error
                                      : color.onSurfaceVariant,
                            ),
                          ),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              selectedMirrorId = value;
                            });
                          },
                        );
                      }),
                      if (selectedMirrorId == PluginService.githubMirrorCustom) ...[
                        const SizedBox(height: 6),
                        TextField(
                          controller: customController,
                          onChanged: (value) {
                            setState(() {
                              customMirrorBaseUrl = value.trim();
                            });
                          },
                          decoration: const InputDecoration(
                            labelText: '自定义代理地址',
                            hintText: '例如：https://my-mirror.example',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton.icon(
                  onPressed:
                      isTesting
                          ? null
                          : () async {
                            setState(() {
                              isTesting = true;
                            });
                            await provider.probeGithubMirrors();
                            if (!dialogContext.mounted) return;
                            setState(() {
                              latencies = Map<String, int?>.from(
                                provider.mirrorProbeLatenciesMs,
                              );
                              isTesting = false;
                            });
                          },
                  icon:
                      isTesting
                          ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.speed_rounded),
                  label: Text(isTesting ? '测速中' : '测速'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed:
                      provider.isBusy ||
                              isTesting ||
                              (selectedMirrorId ==
                                      PluginService.githubMirrorCustom &&
                                  PluginService.normalizeCustomMirrorBaseUrl(
                                        customController.text,
                                      ).isEmpty)
                          ? null
                          : () async {
                            Navigator.of(dialogContext).pop();
                            await provider.setGithubMirrorConfig(
                              mirrorId: selectedMirrorId,
                              customMirrorBaseUrl: customController.text,
                              refreshManifestAfterChange: true,
                            );
                          },
                  child: const Text('保存并刷新'),
                ),
              ],
            );
          },
        );
      },
    );
    customController.dispose();
  }

  /// 安装前置缺失时弹窗提示，并展示当前插件声明的前置插件列表。
  ///
  /// 该弹窗只做引导，不会自动安装前置插件。
  Future<void> _showRequiredPluginsDialog({
    required BuildContext context,
    required PluginProvider provider,
    required PluginDefinition plugin,
  }) async {
    final requiredPluginIds =
        plugin.requiredPluginIds
            .where((item) => item.trim().isNotEmpty && item != plugin.id)
            .toList();
    if (requiredPluginIds.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final color = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('请先安装前置插件'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('安装“${plugin.name}”前，需要先安装以下插件：'),
                const SizedBox(height: 10),
                ...requiredPluginIds.map((requiredId) {
                  final installed = provider.isInstalled(requiredId);
                  final label = provider.pluginDisplayLabel(requiredId);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          installed
                              ? Icons.check_circle_rounded
                              : Icons.error_outline_rounded,
                          size: 16,
                          color: installed ? Colors.green : color.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$label  ${installed ? "(已安装)" : "(未安装)"}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color:
                                  installed
                                      ? color.onSurface
                                      : color.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 4),
                Text(
                  '请先安装未安装项，再安装当前插件。',
                  style: TextStyle(
                    fontSize: 12,
                    color: color.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  /// 构建单个插件卡片。
  ///
  /// 交互规则：
  /// - 已安装：点击进入详情页。
  /// - 未安装：点击无操作，仅右侧按钮可触发安装。
  Widget _buildPluginCard(
    BuildContext context,
    PluginProvider provider,
    PluginDefinition plugin,
  ) {
    final color = Theme.of(context).colorScheme;
    final state = provider.stateForPlugin(plugin.id);
    final installed = provider.isInstalled(plugin.id);
    final enabled = provider.isPluginEnabled(plugin.id);
    final statusText = installed ? (enabled ? '运行中' : '已暂停') : '未安装';
    final statusColor =
        installed
            ? (enabled ? Colors.green : color.error)
            : color.onSurfaceVariant;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap:
            installed
                ? () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PluginDetailPage(pluginId: plugin.id),
                    ),
                  );
                }
                : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plugin.name,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      plugin.description.isEmpty
                          ? '作者：${plugin.author} · v${plugin.version}'
                          : plugin.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: color.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          _stateText(state),
                          style: TextStyle(
                            color: _stateColor(context, state),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // 两个横向操作按钮：启用/暂停(未安装时为下载)、README。
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: installed ? (enabled ? '暂停插件' : '启用插件') : '安装插件',
                    onPressed:
                        provider.isBusy
                            ? null
                            : () async {
                              if (!installed) {
                                // 安装前先显式检查前置插件，缺失时给出可读弹窗。
                                final missingRequiredPluginIds =
                                    provider.missingRequiredPluginIdsFor(plugin.id);
                                if (missingRequiredPluginIds.isNotEmpty) {
                                  await _showRequiredPluginsDialog(
                                    context: context,
                                    provider: provider,
                                    plugin: plugin,
                                  );
                                  return;
                                }
                                await provider.installPlugin(plugin.id);
                                return;
                              }
                              await provider.togglePluginEnabled(plugin.id, !enabled);
                            },
                    icon: Icon(
                      !installed
                          ? Icons.download_rounded
                          : enabled
                          ? Icons.pause_circle_outline
                          : Icons.play_circle_outline,
                    ),
                  ),
                  IconButton(
                    tooltip: '查看 README',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder:
                              (_) => PluginReadmePage(
                                pluginId: plugin.id,
                              ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.article_outlined),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建插件列表区域。
  ///
  /// 空态文案由调用方传入，以区分“无数据”和“搜索无结果”。
  Widget _buildPluginList(
    BuildContext context,
    PluginProvider provider,
    List<PluginDefinition> list,
    String emptyText,
  ) {
    final color = Theme.of(context).colorScheme;
    if (list.isEmpty) {
      return Center(
        child: Text(
          emptyText,
          style: TextStyle(
            color: color.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final plugin = list[index];
        return _buildPluginCard(context, provider, plugin);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PluginProvider>();
    final color = Theme.of(context).colorScheme;
    final plugins = provider.plugins;
    final installedPlugins = _filterPlugins(
      plugins.where((plugin) => provider.isInstalled(plugin.id)).toList(),
    );
    final marketPlugins = _filterPlugins(plugins);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('插件中心'),
          actions: [
            IconButton(
              tooltip: '镜像设置',
              onPressed:
                  provider.isBusy
                      ? null
                      : () => _showMirrorDialog(context, provider),
              icon: const Icon(Icons.language_rounded),
            ),
            // 暂时隐藏本地导入入口，避免与远程清单流程混淆。
            IconButton(
              tooltip: '刷新清单',
              onPressed: provider.isBusy ? null : provider.refreshManifest,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '已安装插件'),
              Tab(text: '插件市场'),
            ],
          ),
        ),
        body:
            !provider.isInitialized
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              provider.lastError!,
                              style: TextStyle(
                                color: color.onErrorContainer,
                                fontSize: 12.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed:
                                    provider.isBusy
                                        ? null
                                        : () => _showMirrorDialog(
                                          context,
                                          provider,
                                        ),
                                icon: const Icon(Icons.public_rounded, size: 16),
                                label: const Text('切换镜像'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (provider.isInstalling)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                        child: LinearProgressIndicator(
                          value:
                              provider.downloadProgress > 0 &&
                                      provider.downloadProgress <= 1
                                  ? provider.downloadProgress
                                  : null,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) {
                          setState(() {
                            _searchKeyword = value;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: '搜索插件名称或介绍',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon:
                              _searchKeyword.trim().isEmpty
                                  ? null
                                  : IconButton(
                                    tooltip: '清空搜索',
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _searchKeyword = '';
                                      });
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildPluginList(
                            context,
                            provider,
                            installedPlugins,
                            _searchKeyword.trim().isEmpty
                                ? '暂无已安装插件'
                                : '没有匹配的已安装插件',
                          ),
                          _buildPluginList(
                            context,
                            provider,
                            marketPlugins,
                            _searchKeyword.trim().isEmpty
                                ? '暂无插件，请先刷新清单'
                                : '没有匹配的插件',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
      ),
    );
  }
}
