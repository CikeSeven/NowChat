import 'package:flutter/material.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../widgets/model_selector_bottom_sheet.dart.dart';

/// 全局默认对话参数设置页。
class DefaultChatParamsPage extends StatefulWidget {
  const DefaultChatParamsPage({super.key});

  @override
  State<DefaultChatParamsPage> createState() => _DefaultChatParamsPageState();
}

/// _DefaultChatParamsPageState 视图状态。
class _DefaultChatParamsPageState extends State<DefaultChatParamsPage> {
  final TextEditingController _maxTokensController = TextEditingController();
  final TextEditingController _maxTurnsController = TextEditingController();
  final TextEditingController _maxToolCallsController = TextEditingController();

  bool _initialized = false;
  String? _providerId;
  String? _model;
  double _temperature = SettingsProvider.defaultTemperatureValue;
  double _topP = SettingsProvider.defaultTopPValue;
  bool _streaming = SettingsProvider.defaultStreamingValue;
  bool _toolCallingEnabled = SettingsProvider.defaultToolCallingEnabledValue;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _syncFromSettings(context.read<SettingsProvider>());
  }

  @override
  void dispose() {
    _maxTokensController.dispose();
    _maxTurnsController.dispose();
    _maxToolCallsController.dispose();
    super.dispose();
  }

  /// 将界面状态与当前 SettingsProvider 值同步。
  void _syncFromSettings(SettingsProvider settings) {
    _providerId = settings.defaultProviderId;
    _model = settings.defaultModel;
    _temperature = settings.defaultTemperature;
    _topP = settings.defaultTopP;
    _streaming = settings.defaultStreaming;
    _toolCallingEnabled = settings.defaultToolCallingEnabled;
    _maxTokensController.text = settings.defaultMaxTokens.toString();
    _maxTurnsController.text = settings.defaultMaxConversationTurns.toString();
    _maxToolCallsController.text = settings.defaultMaxToolCalls.toString();
  }

  /// 打开模型选择弹窗，选择后立即持久化默认模型。
  Future<void> _showModelSelector() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      isDismissible: true,
      enableDrag: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      builder: (sheetContext) {
        return ModelSelectorBottomSheet(
          providerId: _providerId,
          model: _model,
          onModelSelected: (providerId, model) {
            Navigator.of(sheetContext).pop();
            _applyAndSaveModel(providerId: providerId, model: model);
          },
        );
      },
    );
  }

  /// 应用并立即保存默认模型，避免用户额外点击保存按钮。
  Future<void> _applyAndSaveModel({
    required String? providerId,
    required String? model,
  }) async {
    setState(() {
      _providerId = providerId;
      _model = model;
    });
    await context.read<SettingsProvider>().setDefaultModel(
      providerId: providerId,
      model: model,
    );
  }

  /// 保存全部默认参数到本地设置。
  Future<void> _save() async {
    final maxTokens = int.tryParse(_maxTokensController.text.trim());
    final maxTurns = int.tryParse(_maxTurnsController.text.trim());
    final maxToolCalls = int.tryParse(_maxToolCallsController.text.trim());
    if (maxTokens == null || maxTokens <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('最大输出tokens 必须大于 0')));
      return;
    }
    if (maxTurns == null || maxTurns <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('最大消息轮次必须大于 0')));
      return;
    }
    if (maxToolCalls == null || maxToolCalls <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('工具调用上限必须大于 0')));
      return;
    }

    final settings = context.read<SettingsProvider>();
    await settings.setDefaultModel(providerId: _providerId, model: _model);
    await settings.setDefaultTemperature(_temperature);
    await settings.setDefaultTopP(_topP);
    await settings.setDefaultMaxTokens(maxTokens);
    await settings.setDefaultMaxConversationTurns(maxTurns);
    await settings.setDefaultStreaming(_streaming);
    await settings.setDefaultToolCallingEnabled(_toolCallingEnabled);
    await settings.setDefaultMaxToolCalls(maxToolCalls);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// 二次确认后恢复默认值。
  Future<void> _restoreDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('恢复默认参数'),
            content: const Text('确认恢复默认对话参数吗？此操作会覆盖当前设置。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('恢复'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    await context.read<SettingsProvider>().restoreDefaultChatParams();
    if (!mounted) return;
    setState(() {
      _syncFromSettings(context.read<SettingsProvider>());
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已恢复默认参数')));
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final selectedProvider =
        _providerId == null ? null : chatProvider.getProviderById(_providerId!);
    final selectedModelDisplay =
        selectedProvider != null && _model != null
            ? selectedProvider.displayNameForModel(_model!)
            : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('默认对话参数'),
        actions: [
          TextButton(
            onPressed: _restoreDefaults,
            child: const Text('恢复默认'),
          ),
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('默认模型'),
            subtitle: Text(
              selectedModelDisplay == null || _model == null
                  ? '未设置'
                  : '${selectedProvider?.name ?? '未知提供方'} · $selectedModelDisplay',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_model != null)
                  IconButton(
                    tooltip: '清除',
                    onPressed:
                        () => _applyAndSaveModel(providerId: null, model: null),
                    icon: const Icon(Icons.clear_rounded),
                  ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
            onTap: _showModelSelector,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _maxTokensController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              labelText: '默认 max tokens',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _maxTurnsController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              labelText: '默认最大消息轮次',
              helperText: '按“用户+AI”为 1 轮',
            ),
          ),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('默认 Temperature'),
            subtitle: Slider(
              min: 0,
              max: 2,
              divisions: 40,
              value: _temperature,
              label: _temperature.toStringAsFixed(2),
              onChanged: (value) {
                setState(() {
                  _temperature = value;
                });
              },
            ),
            trailing: Text(_temperature.toStringAsFixed(2)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('默认 top_p'),
            subtitle: Slider(
              min: 0,
              max: 1,
              divisions: 40,
              value: _topP,
              label: _topP.toStringAsFixed(2),
              onChanged: (value) {
                setState(() {
                  _topP = value;
                });
              },
            ),
            trailing: Text(_topP.toStringAsFixed(2)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('默认流式输出'),
            value: _streaming,
            onChanged: (value) {
              setState(() {
                _streaming = value;
              });
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用工具调用'),
            subtitle: const Text('开启后大模型可以调用工具'),
            value: _toolCallingEnabled,
            onChanged: (value) {
              setState(() {
                _toolCallingEnabled = value;
              });
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _maxToolCallsController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              labelText: '默认工具调用上限',
              helperText: '单次请求最多允许工具调用次数，默认 ${SettingsProvider.defaultMaxToolCallsValue}',
            ),
          ),
        ],
      ),
    );
  }
}
