import 'package:flutter/material.dart';
import 'package:now_chat/core/models/agent_profile.dart';
import 'package:now_chat/providers/agent_provider.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:now_chat/providers/settings_provider.dart';
import 'package:now_chat/ui/widgets/model_selector_bottom_sheet.dart.dart';
import 'package:provider/provider.dart';

/// 智能体新增/编辑页面。
class AgentFormPage extends StatefulWidget {
  final String? agentId;

  const AgentFormPage({super.key, this.agentId});

  @override
  State<AgentFormPage> createState() => _AgentFormPageState();
}

class _AgentFormPageState extends State<AgentFormPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _summaryController = TextEditingController();
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _maxTokensController = TextEditingController();

  bool _initialized = false;
  bool _isEditing = false;
  String? _agentId;
  bool _overrideParams = false;

  String? _providerId;
  String? _model;
  double _temperature = SettingsProvider.defaultTemperatureValue;
  double _topP = SettingsProvider.defaultTopPValue;
  bool _streaming = SettingsProvider.defaultStreamingValue;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final settings = context.read<SettingsProvider>();
    _providerId = null;
    _model = null;
    _temperature = settings.defaultTemperature;
    _topP = settings.defaultTopP;
    _streaming = settings.defaultStreaming;
    _maxTokensController.text = settings.defaultMaxTokens.toString();

    final agentId = widget.agentId;
    if (agentId == null) return;
    final existing = context.read<AgentProvider>().getById(agentId);
    if (existing == null) return;

    _isEditing = true;
    _agentId = existing.id;
    _nameController.text = existing.name;
    _summaryController.text = existing.summary;
    _promptController.text = existing.prompt;

    if ((existing.providerId ?? '').trim().isNotEmpty &&
        (existing.model ?? '').trim().isNotEmpty) {
      _providerId = existing.providerId;
      _model = existing.model;
    }

    _overrideParams =
        existing.temperature != null ||
        existing.topP != null ||
        existing.maxTokens != null ||
        existing.isStreaming != null;
    if (_overrideParams) {
      _temperature = existing.temperature ?? _temperature;
      _topP = existing.topP ?? _topP;
      _streaming = existing.isStreaming ?? _streaming;
      _maxTokensController.text =
          (existing.maxTokens ?? settings.defaultMaxTokens).toString();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _summaryController.dispose();
    _promptController.dispose();
    _maxTokensController.dispose();
    super.dispose();
  }

  Future<void> _showModelSelector() async {
    final settings = context.read<SettingsProvider>();
    final initialProviderId = _providerId ?? settings.defaultProviderId;
    final initialModel = _model ?? settings.defaultModel;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      builder: (sheetContext) {
        return ModelSelectorBottomSheet(
          providerId: initialProviderId,
          model: initialModel,
          onModelSelected: (providerId, model) {
            setState(() {
              _providerId = providerId;
              _model = model;
            });
            Navigator.of(sheetContext).pop();
          },
        );
      },
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final summary = _summaryController.text.trim();
    final prompt = _promptController.text.trim();
    if (name.isEmpty) {
      _showSnackBar('名称不能为空');
      return;
    }
    if (summary.isEmpty) {
      _showSnackBar('简述不能为空');
      return;
    }
    if (prompt.isEmpty) {
      _showSnackBar('提示词不能为空');
      return;
    }

    final normalizedProviderId = (_providerId ?? '').trim();
    final normalizedModel = (_model ?? '').trim();
    final hasProvider = normalizedProviderId.isNotEmpty;
    final hasModel = normalizedModel.isNotEmpty;
    if (hasProvider != hasModel) {
      _showSnackBar('模型配置不完整，请重新选择模型或清除');
      return;
    }

    int? maxTokens;
    if (_overrideParams) {
      maxTokens = int.tryParse(_maxTokensController.text.trim());
      if (maxTokens == null || maxTokens <= 0) {
        _showSnackBar('max tokens 必须大于 0');
        return;
      }
    }

    final providerId = hasProvider ? normalizedProviderId : null;
    final model = hasModel ? normalizedModel : null;
    final temperature = _overrideParams ? _temperature : null;
    final topP = _overrideParams ? _topP : null;
    final streaming = _overrideParams ? _streaming : null;

    final agentProvider = context.read<AgentProvider>();
    if (_isEditing) {
      final existing = _agentId == null ? null : agentProvider.getById(_agentId!);
      if (existing == null) {
        _showSnackBar('智能体不存在');
        return;
      }
      existing.applyUpdate(
        name: name,
        summary: summary,
        prompt: prompt,
        providerId: providerId,
        model: model,
        temperature: temperature,
        topP: topP,
        maxTokens: maxTokens,
        isStreaming: streaming,
      );
      await agentProvider.updateAgent(existing);
    } else {
      final profile = AgentProfile.create(
        name: name,
        summary: summary,
        prompt: prompt,
        providerId: providerId,
        model: model,
        temperature: temperature,
        topP: topP,
        maxTokens: maxTokens,
        isStreaming: streaming,
      );
      await agentProvider.createAgent(profile);
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _showSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final settings = context.watch<SettingsProvider>();
    final selectedProvider =
        _providerId == null ? null : chatProvider.getProviderById(_providerId!);
    final selectedModelDisplay = selectedProvider != null && _model != null
        ? selectedProvider.displayNameForModel(_model!)
        : null;
    final defaultProviderId = settings.defaultProviderId;
    final defaultModel = settings.defaultModel;
    final defaultProvider = defaultProviderId == null
        ? null
        : chatProvider.getProviderById(defaultProviderId);
    final defaultModelDisplay = defaultProvider != null && defaultModel != null
        ? defaultProvider.displayNameForModel(defaultModel)
        : null;
    final hasBoundModel = selectedProvider != null && selectedModelDisplay != null;
    final modelSubtitle = hasBoundModel
        ? '已绑定：${selectedProvider.name} · $selectedModelDisplay'
        : (defaultProvider != null && defaultModelDisplay != null
            ? '默认：${defaultProvider.name} · $defaultModelDisplay'
            : '未设置（请先在设置中配置默认模型或在此绑定模型）');

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑智能体' : '新建智能体'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              labelText: '智能体名称',
              hintText: '例如：翻译助手',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _summaryController,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              labelText: '简述',
              hintText: '列表展示文本（最多建议两行）',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _promptController,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: '提示词',
              hintText: '输入该智能体的 system prompt',
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: const Icon(Icons.smart_toy_outlined),
                  title: const Text('模型'),
                  subtitle: Text(modelSubtitle),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_model != null)
                        IconButton(
                          tooltip: '清除绑定，回退默认模型',
                          onPressed: () {
                            setState(() {
                              _providerId = null;
                              _model = null;
                            });
                          },
                          icon: const Icon(Icons.clear_rounded),
                        ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                  onTap: _showModelSelector,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('覆盖默认参数'),
                  subtitle: const Text('温度、top_p、max tokens、流式输出'),
                  value: _overrideParams,
                  onChanged: (value) {
                    setState(() {
                      _overrideParams = value;
                    });
                  },
                ),
                if (_overrideParams) ...[
                  ListTile(
                    title: const Text('Temperature'),
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
                    title: const Text('top_p'),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: TextField(
                      controller: _maxTokensController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        labelText: 'max tokens',
                      ),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('流式输出'),
                    value: _streaming,
                    onChanged: (value) {
                      setState(() {
                        _streaming = value;
                      });
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
