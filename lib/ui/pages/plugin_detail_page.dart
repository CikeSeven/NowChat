import 'package:flutter/material.dart';
import 'package:now_chat/core/models/plugin_manifest_v2.dart';
import 'package:now_chat/core/models/plugin_ui_runtime.dart';
import 'package:now_chat/providers/plugin_provider.dart';
import 'package:provider/provider.dart';

/// 插件专属页面：配置、工具开关、Hook 展示与动作执行。
class PluginDetailPage extends StatefulWidget {
  final String pluginId;

  const PluginDetailPage({
    super.key,
    required this.pluginId,
  });

  @override
  State<PluginDetailPage> createState() => _PluginDetailPageState();
}

class _PluginDetailPageState extends State<PluginDetailPage> {
  final Map<String, TextEditingController> _uiTextControllers =
      <String, TextEditingController>{};
  static const int _hookLogPreviewMaxLength = 220;
  bool _isToolsExpanded = false;
  bool _isHooksExpanded = false;

  @override
  void initState() {
    super.initState();
    // 页面进入后主动加载插件 DSL，避免用户先点交互才触发首次解析。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PluginProvider>().loadPluginUiPage(pluginId: widget.pluginId);
    });
  }

  @override
  void dispose() {
    for (final controller in _uiTextControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _formatSizeBytes(int? sizeBytes) {
    if (sizeBytes == null || sizeBytes <= 0) return '未知';
    final kb = sizeBytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }

  int _sumPackageSize(List<PluginPackage> packages) {
    var sum = 0;
    for (final pkg in packages) {
      sum += pkg.sizeBytes ?? 0;
    }
    return sum;
  }

  /// 压缩并截断 Hook 日志正文，避免设置页单条日志过长撑爆布局。
  String _formatHookLogMessage(String message) {
    final normalized = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= _hookLogPreviewMaxLength) {
      return normalized;
    }
    return '${normalized.substring(0, _hookLogPreviewMaxLength)}...';
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

  TextEditingController _ensureUiTextController(
    String componentId,
    String value,
  ) {
    final existing = _uiTextControllers[componentId];
    if (existing != null) {
      // Python 返回新状态后，同步输入框默认值，避免 Flutter 端状态漂移。
      if (existing.text != value) {
        existing
          ..text = value
          ..selection = TextSelection.collapsed(offset: value.length);
      }
      return existing;
    }
    final controller = TextEditingController(text: value);
    _uiTextControllers[componentId] = controller;
    return controller;
  }

  Future<void> _dispatchUiEvent({
    required PluginProvider provider,
    required String pluginId,
    required String componentId,
    required String eventType,
    dynamic value,
  }) async {
    final message = await provider.dispatchPluginUiEvent(
      pluginId: pluginId,
      componentId: componentId,
      eventType: eventType,
      value: value,
    );
    if (!mounted || message == null || message.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// 二次确认弹窗，返回 `true` 表示用户确认执行。
  Future<bool> _confirmAction({
    required String title,
    required String content,
    required String confirmText,
    bool isDanger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style:
                  isDanger
                      ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(dialogContext).colorScheme.error,
                        foregroundColor:
                            Theme.of(dialogContext).colorScheme.onError,
                      )
                      : null,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmText),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PluginProvider>();
    final color = Theme.of(context).colorScheme;
    final plugin = provider.getPluginById(widget.pluginId);
    if (plugin == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('插件')),
        body: const Center(child: Text('插件不存在或已移除')),
      );
    }

    final installed = provider.isInstalled(plugin.id);
    final enabled = provider.isPluginEnabled(plugin.id);
    final state = provider.stateForPlugin(plugin.id);
    final totalSize = _sumPackageSize(plugin.packages);
    final pluginUiState = provider.pluginUiPage(plugin.id);
    final pluginUiError = provider.pluginUiError(plugin.id);
    final isPluginUiLoading = provider.isPluginUiLoading(plugin.id);
    final pluginPageTitle = (pluginUiState?.title ?? '').trim().isNotEmpty
        ? pluginUiState!.title
        : plugin.name;
    final relatedHookLogs = provider.hookLogs
        .where((item) => item.pluginId == plugin.id)
        .toList()
        .reversed
        .take(10)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          pluginPageTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plugin.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: color.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    plugin.description.isEmpty ? '无说明' : plugin.description,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: color.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _MetaChip(label: '作者 ${plugin.author}'),
                      _MetaChip(label: '版本 v${plugin.version}'),
                      _MetaChip(label: '类型 ${plugin.type}'),
                      _MetaChip(label: '工具 ${plugin.tools.length}'),
                      _MetaChip(label: 'Hook ${plugin.hooks.length}'),
                      _MetaChip(label: '大小 ${_formatSizeBytes(totalSize)}'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed:
                              provider.isBusy
                                  ? null
                                  : () async {
                                    final confirmed = await _confirmAction(
                                      title: '重新安装插件',
                                      content:
                                          '将重新下载安装并覆盖当前插件文件，确定继续吗？',
                                      confirmText: '重新安装',
                                    );
                                    if (!confirmed || !mounted) return;
                                    await provider.installPlugin(plugin.id);
                                    if (!mounted) return;
                                    await provider.loadPluginUiPage(
                                      pluginId: plugin.id,
                                    );
                                  },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('重新安装'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              provider.isBusy || !installed
                                  ? null
                                  : () async {
                                    final confirmed = await _confirmAction(
                                      title: '卸载插件',
                                      content:
                                          '卸载后将移除插件文件与本地状态，确定卸载吗？',
                                      confirmText: '卸载',
                                      isDanger: true,
                                    );
                                    if (!confirmed || !mounted) return;
                                    await provider.uninstallPlugin(plugin.id);
                                    if (!mounted) return;
                                    if (!provider.isInstalled(plugin.id)) {
                                      Navigator.of(context).pop();
                                    }
                                  },
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('卸载插件'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用插件'),
                    subtitle: Text(installed ? '插件启用后其工具与 Hook 生效' : '请先安装'),
                    value: installed && enabled,
                    onChanged: (!installed || provider.isBusy)
                        ? null
                        : (value) => provider.togglePluginEnabled(plugin.id, value),
                  ),
                  Text(
                    '状态：${_stateText(state)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: color.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: ExpansionTile(
              initiallyExpanded: _isToolsExpanded,
              onExpansionChanged: (value) => setState(() => _isToolsExpanded = value),
              tilePadding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              title: Text(
                '工具开关',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color.onSurface,
                ),
              ),
              children: [
                if (plugin.tools.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '该插件没有声明工具',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: color.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  ...plugin.tools.map((tool) {
                    final toolEnabled = provider.isToolEnabled(plugin.id, tool.name);
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tool.name),
                      subtitle: Text(
                        tool.description.isEmpty ? tool.runtime : tool.description,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: color.onSurfaceVariant,
                        ),
                      ),
                      value: toolEnabled,
                      onChanged: (!installed || !enabled || provider.isBusy)
                          ? null
                          : (value) =>
                              provider.toggleToolEnabled(plugin.id, tool.name, value),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: ExpansionTile(
              initiallyExpanded: _isHooksExpanded,
              onExpansionChanged: (value) => setState(() => _isHooksExpanded = value),
              tilePadding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              title: Text(
                'Hook 事件',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color.onSurface,
                ),
              ),
              children: [
                if (plugin.hooks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '该插件没有声明 Hook',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: color.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  ...plugin.hooks.map(
                    (hook) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: color.outlineVariant.withAlpha(120),
                          ),
                        ),
                        child: Text(
                          '${hook.event}  ·  ${hook.runtime}  ·  priority ${hook.priority}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: color.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '插件配置',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if ((pluginUiState?.subtitle ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        pluginUiState!.subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: color.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (isPluginUiLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    ),
                  if ((pluginUiError ?? '').trim().isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      decoration: BoxDecoration(
                        color: color.errorContainer.withAlpha(120),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        pluginUiError!,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: color.onErrorContainer,
                        ),
                      ),
                    ),
                  if (!isPluginUiLoading &&
                      (pluginUiError ?? '').trim().isEmpty &&
                      (pluginUiState == null ||
                          pluginUiState.components.where((c) => c.visible).isEmpty))
                    Text(
                      '该插件未提供配置页（pythonNamespace/schema.py）或未声明可见组件',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: color.onSurfaceVariant,
                      ),
                    ),
                  if (pluginUiState != null)
                    ...pluginUiState.components
                        .where((component) => component.visible)
                        .map((component) {
                      switch (component.type) {
                        case PluginUiComponentType.button:
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: (!installed ||
                                        !enabled ||
                                        provider.isBusy ||
                                        !component.enabled)
                                    ? null
                                    : () => _dispatchUiEvent(
                                          provider: provider,
                                          pluginId: plugin.id,
                                          componentId: component.id,
                                          eventType: 'button_click',
                                        ),
                                child: Text(
                                  component.label.isEmpty ? component.id : component.label,
                                ),
                              ),
                            ),
                          );
                        case PluginUiComponentType.textInput:
                          final controller = _ensureUiTextController(
                            component.id,
                            component.textValue,
                          );
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (component.label.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      component.label,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: color.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                TextField(
                                  controller: controller,
                                  minLines: component.multiline ? 3 : 1,
                                  maxLines: component.multiline ? 6 : 1,
                                  enabled: installed &&
                                      enabled &&
                                      !provider.isBusy &&
                                      component.enabled,
                                  decoration: InputDecoration(
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                    hintText: component.placeholder ?? '请输入内容',
                                    suffixIcon: IconButton(
                                      onPressed: (!installed ||
                                              !enabled ||
                                              provider.isBusy ||
                                              !component.enabled)
                                          ? null
                                          : () => _dispatchUiEvent(
                                                provider: provider,
                                                pluginId: plugin.id,
                                                componentId: component.id,
                                                eventType: 'input_submit',
                                                value: controller.text,
                                              ),
                                      icon: const Icon(Icons.send_rounded),
                                    ),
                                  ),
                                  onSubmitted: (value) => _dispatchUiEvent(
                                    provider: provider,
                                    pluginId: plugin.id,
                                    componentId: component.id,
                                    eventType: 'input_submit',
                                    value: value,
                                  ),
                                ),
                              ],
                            ),
                          );
                        case PluginUiComponentType.toggle:
                          return SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              component.label.isEmpty ? component.id : component.label,
                            ),
                            subtitle: component.description.isEmpty
                                ? null
                                : Text(
                                    component.description,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: color.onSurfaceVariant,
                                    ),
                                  ),
                            value: component.boolValue,
                            onChanged: (!installed ||
                                    !enabled ||
                                    provider.isBusy ||
                                    !component.enabled)
                                ? null
                                : (value) => _dispatchUiEvent(
                                      provider: provider,
                                      pluginId: plugin.id,
                                      componentId: component.id,
                                      eventType: 'switch_toggle',
                                      value: value,
                                    ),
                          );
                        case PluginUiComponentType.select:
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: DropdownButtonFormField<String>(
                              value: component.selectedValue.isEmpty
                                  ? null
                                  : component.selectedValue,
                              items: component.options
                                  .map(
                                    (item) => DropdownMenuItem<String>(
                                      value: item.value,
                                      child: Text(item.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (!installed ||
                                      !enabled ||
                                      provider.isBusy ||
                                      !component.enabled)
                                  ? null
                                  : (value) => _dispatchUiEvent(
                                        provider: provider,
                                        pluginId: plugin.id,
                                        componentId: component.id,
                                        eventType: 'select_change',
                                        value: value ?? '',
                                      ),
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                isDense: true,
                                labelText:
                                    component.label.isEmpty ? component.id : component.label,
                                helperText:
                                    component.description.isEmpty ? null : component.description,
                              ),
                            ),
                          );
                      }
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hook 日志',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (relatedHookLogs.isEmpty)
                    Text(
                      '暂无 Hook 日志',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: color.onSurfaceVariant,
                      ),
                    )
                  else
                    ...relatedHookLogs.map(
                      (log) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '[${log.time.toIso8601String()}] ${log.event} · ${log.ok ? "OK" : "ERR"} · ${_formatHookLogMessage(log.message)}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: log.ok ? color.onSurfaceVariant : color.error,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;

  const _MetaChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.secondaryContainer.withAlpha(90),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          color: color.onSecondaryContainer,
        ),
      ),
    );
  }
}
