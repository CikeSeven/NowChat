import 'package:flutter/material.dart';
import 'package:now_chat/core/models/ai_provider_config.dart';
import 'package:now_chat/core/provider/provider_catalog.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

class ProviderFormPage extends StatefulWidget {
  final String? providerId;

  const ProviderFormPage({super.key, this.providerId});

  @override
  State<ProviderFormPage> createState() => _ProviderFormPageState();
}

class _ProviderFormPageState extends State<ProviderFormPage> {
  static const int _collapsedPresetCount = 8;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _presetSearchController = TextEditingController();

  bool _initialized = false;
  bool _isEditing = false;
  bool _keyObscure = true;
  bool _loadingModels = false;
  bool _showAllPresets = false;
  String? _loadError;

  String _selectedPresetId = ProviderCatalog.presets.first.id;
  ProviderType _selectedType = ProviderCatalog.presets.first.type;
  RequestMode _selectedRequestMode = ProviderCatalog.presets.first.requestMode;

  List<String> _models = <String>[];
  Map<String, String> _modelRemarks = <String, String>{};
  Map<String, ModelFeatureOptions> _modelCapabilities =
      <String, ModelFeatureOptions>{};
  List<String> _fetchedModels = <String>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final chatProvider = context.read<ChatProvider>();
    final providerId = widget.providerId;
    if (providerId != null) {
      final existing = chatProvider.getProviderById(providerId);
      if (existing != null) {
        _isEditing = true;
        _nameController.text = existing.name;
        _baseUrlController.text = existing.baseUrl ?? '';
        _pathController.text = existing.urlPath ?? '';
        _apiKeyController.text = existing.apiKey ?? '';
        _selectedRequestMode = existing.requestMode;
        _selectedType = _typeForMode(_selectedRequestMode);
        _models = List<String>.from(existing.models);
        _modelRemarks = Map<String, String>.from(existing.modelRemarks);
        _modelCapabilities = Map<String, ModelFeatureOptions>.from(
          existing.modelCapabilities,
        );
        _selectedPresetId = ProviderCatalog.matchFromConfig(existing).id;
        return;
      }
    }

    final preset = ProviderCatalog.findById('openai');
    _selectedPresetId = preset.id;
    _selectedRequestMode = preset.requestMode;
    _selectedType = _typeForMode(_selectedRequestMode);
    _nameController.text = preset.name;
    _baseUrlController.text = preset.baseUrl;
    _pathController.text = preset.path;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _pathController.dispose();
    _apiKeyController.dispose();
    _presetSearchController.dispose();
    super.dispose();
  }

  bool get _canSave {
    return _nameController.text.trim().isNotEmpty &&
        _baseUrlController.text.trim().isNotEmpty &&
        _pathController.text.trim().isNotEmpty;
  }

  Future<void> _save() async {
    if (!_canSave) return;

    final chatProvider = context.read<ChatProvider>();
    final payload = AIProviderConfig(
      id: widget.providerId ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      type: _selectedType,
      requestMode: _selectedRequestMode,
      baseUrl: _baseUrlController.text.trim(),
      urlPath: _pathController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      models: List<String>.from(_models),
      modelRemarks: Map<String, String>.from(_modelRemarks),
      modelCapabilities: Map<String, ModelFeatureOptions>.from(
        _modelCapabilities,
      ),
    );

    if (_isEditing && widget.providerId != null) {
      await chatProvider.updateProvider(
        widget.providerId!,
        name: payload.name,
        type: payload.type,
        requestMode: payload.requestMode,
        baseUrl: payload.baseUrl,
        urlPath: payload.urlPath,
        apiKey: payload.apiKey,
        models: payload.models,
        modelRemarks: payload.modelRemarks,
        modelCapabilities: payload.modelCapabilities,
      );
    } else {
      await chatProvider.createNewProvider(payload);
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _onSelectPreset(String presetId) {
    final previous = ProviderCatalog.findById(_selectedPresetId);
    final next = ProviderCatalog.findById(presetId);
    final currentName = _nameController.text.trim();
    final shouldReplaceName =
        currentName.isEmpty || currentName == previous.name;

    setState(() {
      _selectedPresetId = presetId;
      _selectedRequestMode = next.requestMode;
      _selectedType = _typeForMode(_selectedRequestMode);
      if (shouldReplaceName) {
        _nameController.text = next.name;
      }
      _baseUrlController.text = next.baseUrl;
      _pathController.text = next.path;
    });
  }

  ProviderType _typeForMode(RequestMode mode) {
    switch (mode) {
      case RequestMode.geminiGenerateContent:
        return ProviderType.gemini;
      case RequestMode.claudeMessages:
        return ProviderType.claude;
      case RequestMode.openaiChat:
        return ProviderType.openaiCompatible;
    }
  }

  void _onRequestModeChanged(RequestMode mode) {
    final previousMode = _selectedRequestMode;
    setState(() {
      _selectedRequestMode = mode;
      _selectedType = _typeForMode(mode);

      final currentPath = _pathController.text.trim();
      if (currentPath.isEmpty || currentPath == previousMode.defaultPath) {
        _pathController.text = mode.defaultPath;
      }
      if (_baseUrlController.text.trim().isEmpty) {
        _baseUrlController.text = _selectedType.defaultBaseUrl;
      }
    });
  }

  void _upsertModel(
    String model, {
    String? remark,
    bool? supportsVision,
    bool? supportsTools,
  }) {
    final normalizedModel = model.trim();
    if (normalizedModel.isEmpty) return;

    setState(() {
      if (!_models.contains(normalizedModel)) {
        _models.add(normalizedModel);
      }
      final normalizedRemark = (remark ?? '').trim();
      if (normalizedRemark.isEmpty) {
        _modelRemarks.remove(normalizedModel);
      } else {
        _modelRemarks[normalizedModel] = normalizedRemark;
      }

      final previous =
          _modelCapabilities[normalizedModel] ?? const ModelFeatureOptions();
      final next = previous.copyWith(
        supportsVision: supportsVision,
        supportsTools: supportsTools,
      );
      if (next.hasAnyCapability) {
        _modelCapabilities[normalizedModel] = next;
      } else {
        _modelCapabilities.remove(normalizedModel);
      }
    });
  }

  void _removeModel(String model) {
    setState(() {
      _models.remove(model);
      _modelRemarks.remove(model);
      _modelCapabilities.remove(model);
    });
  }

  void _toggleModelCapability(
    String model, {
    bool? supportsVision,
    bool? supportsTools,
  }) {
    final current = _modelCapabilities[model] ?? const ModelFeatureOptions();
    final next = current.copyWith(
      supportsVision: supportsVision,
      supportsTools: supportsTools,
    );
    setState(() {
      if (next.hasAnyCapability) {
        _modelCapabilities[model] = next;
      } else {
        _modelCapabilities.remove(model);
      }
    });
  }

  Future<void> _showCustomModelDialog({
    String? initialModel,
    String? initialRemark,
    ModelFeatureOptions? initialFeatures,
    bool lockModelName = false,
  }) async {
    final modelController = TextEditingController(text: initialModel ?? '');
    final remarkController = TextEditingController(text: initialRemark ?? '');
    bool supportsVision = initialFeatures?.supportsVision ?? false;
    bool supportsTools = initialFeatures?.supportsTools ?? false;
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(lockModelName ? '编辑模型信息' : '手动添加模型'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: modelController,
                    readOnly: lockModelName,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: '模型名',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: remarkController,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: '备注名（可选）',
                      hintText: '例如：主力模型',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          title: const Text(
                            '支持视觉',
                            style: TextStyle(fontSize: 13),
                          ),
                          value: supportsVision,
                          onChanged: (value) {
                            setDialogState(() {
                              supportsVision = value ?? false;
                            });
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ),
                      Expanded(
                        child: CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          title: const Text(
                            '支持工具',
                            style: TextStyle(fontSize: 13),
                          ),
                          value: supportsTools,
                          onChanged: (value) {
                            setDialogState(() {
                              supportsTools = value ?? false;
                            });
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ),
                    ],
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        errorText!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final model = modelController.text.trim();
                    final remark = remarkController.text.trim();
                    if (model.isEmpty) {
                      setDialogState(() {
                        errorText = '模型名不能为空';
                      });
                      return;
                    }
                    if (!_models.contains(model) ||
                        (lockModelName && initialModel == model)) {
                      _upsertModel(
                        model,
                        remark: remark,
                        supportsVision: supportsVision,
                        supportsTools: supportsTools,
                      );
                      Navigator.of(context).pop();
                      return;
                    }
                    setDialogState(() {
                      errorText = '模型已存在';
                    });
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _fetchModels() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    if (baseUrl.isEmpty) return;

    setState(() {
      _loadingModels = true;
      _loadError = null;
      _fetchedModels = <String>[];
    });

    final tempProvider = AIProviderConfig(
      id: 'temp',
      name:
          _nameController.text.trim().isEmpty
              ? 'temp'
              : _nameController.text.trim(),
      type: _selectedType,
      baseUrl: baseUrl,
      urlPath: _pathController.text.trim(),
      apiKey: apiKey,
      models: const <String>[],
    );

    try {
      final chatProvider = context.read<ChatProvider>();
      final models = await chatProvider.fetchModels(
        tempProvider,
        baseUrl,
        apiKey,
      );
      final uniqueModels =
          models
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      if (!mounted) return;
      setState(() {
        _fetchedModels = uniqueModels;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingModels = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final filteredPresets = ProviderCatalog.search(
      _presetSearchController.text,
    );
    final isSearchingPresets = _presetSearchController.text.trim().isNotEmpty;
    final shouldCollapsePresets =
        !isSearchingPresets &&
        !_showAllPresets &&
        filteredPresets.length > _collapsedPresetCount;
    final visiblePresets =
        shouldCollapsePresets
            ? filteredPresets.take(_collapsedPresetCount).toList()
            : List<ProviderPreset>.from(filteredPresets);
    final selectedInVisible = visiblePresets.any(
      (preset) => preset.id == _selectedPresetId,
    );
    if (shouldCollapsePresets && !selectedInVisible) {
      ProviderPreset? selectedPreset;
      for (final preset in filteredPresets) {
        if (preset.id == _selectedPresetId) {
          selectedPreset = preset;
          break;
        }
      }
      if (selectedPreset != null) {
        visiblePresets.add(selectedPreset);
      }
    }
    final canFetchModels =
        !_loadingModels && _baseUrlController.text.trim().isNotEmpty;
    final addableModels =
        _fetchedModels.where((item) => !_models.contains(item)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑 API' : '新增 API'),
        actions: [
          TextButton(
            onPressed: _canSave ? _save : null,
            child: Text(
              '保存',
              style: TextStyle(
                color:
                    _canSave ? color.primary : color.onSurface.withAlpha(120),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '提供方目录',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: color.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _presetSearchController,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '搜索提供方（例如 OpenAI / Gemini）',
                        prefixIcon: Icon(Icons.search, size: 18),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children:
                          visiblePresets.map((preset) {
                            return ChoiceChip(
                              label: Text(preset.name),
                              selected: _selectedPresetId == preset.id,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              labelPadding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              onSelected: (_) => _onSelectPreset(preset.id),
                            );
                          }).toList(),
                    ),
                    if (!isSearchingPresets &&
                        filteredPresets.length > _collapsedPresetCount) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _showAllPresets = !_showAllPresets;
                            });
                          },
                          icon: Icon(
                            _showAllPresets
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 18,
                          ),
                          label: Text(
                            _showAllPresets
                                ? '收起'
                                : '更多 (${filteredPresets.length - visiblePresets.length})',
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      ProviderCatalog.findById(_selectedPresetId).description,
                      style: TextStyle(
                        fontSize: 12,
                        color: color.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '连接配置',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: color.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _nameController,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'API 名称',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<RequestMode>(
                      value: _selectedRequestMode,
                      items:
                          RequestMode.values
                              .map(
                                (mode) => DropdownMenuItem<RequestMode>(
                                  value: mode,
                                  child: Text(mode.label),
                                ),
                              )
                              .toList(),
                      onChanged: (mode) {
                        if (mode == null) return;
                        _onRequestModeChanged(mode);
                      },
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: '请求方式',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _selectedRequestMode.supportsStreaming
                          ? '当前请求方式支持流式输出'
                          : '当前请求方式暂不支持流式输出，将自动回退普通请求',
                      style: TextStyle(
                        fontSize: 12,
                        color: color.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _baseUrlController,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Base URL',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _pathController,
                      onChanged: (_) => setState(() {}),
                      readOnly: !_selectedType.allowEditPath,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: '请求路径',
                        border: const OutlineInputBorder(),
                        helperText:
                            _selectedType.allowEditPath ? null : '当前协议为固定路径',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _apiKeyController,
                      obscureText: _keyObscure,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'API Key',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _keyObscure
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 18,
                          ),
                          onPressed: () {
                            setState(() {
                              _keyObscure = !_keyObscure;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '预览：${_baseUrlController.text.trim()}${_pathController.text.trim()}',
                      style: TextStyle(
                        fontSize: 12,
                        color: color.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '模型管理',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: color.onSurface,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 4,
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                _showCustomModelDialog();
                              },
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('手动添加'),
                            ),
                            TextButton.icon(
                              onPressed: canFetchModels ? _fetchModels : null,
                              icon: const Icon(Icons.refresh, size: 18),
                              label: Text(_loadingModels ? '获取中...' : '获取模型'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '当前模型',
                      style: TextStyle(
                        fontSize: 13,
                        color: color.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (_models.isEmpty)
                      Text(
                        '暂无模型',
                        style: TextStyle(fontSize: 13, color: color.outline),
                      )
                    else
                      ..._models.map(
                        (model) => _buildCurrentModelListItem(
                          model: model,
                          remark: _modelRemarks[model],
                          features:
                              _modelCapabilities[model] ??
                              const ModelFeatureOptions(),
                          backgroundColor: color.primaryContainer.withAlpha(
                            120,
                          ),
                          onEditRemark: () {
                            _showCustomModelDialog(
                              initialModel: model,
                              initialRemark: _modelRemarks[model],
                              initialFeatures: _modelCapabilities[model],
                              lockModelName: true,
                            );
                          },
                          onToggleVision:
                              (enabled) => _toggleModelCapability(
                                model,
                                supportsVision: enabled,
                              ),
                          onToggleTools:
                              (enabled) => _toggleModelCapability(
                                model,
                                supportsTools: enabled,
                              ),
                          onRemove: () => _removeModel(model),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_loadingModels ||
                _loadError != null ||
                _fetchedModels.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '可添加模型',
                        style: TextStyle(
                          fontSize: 13,
                          color: color.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (_loadingModels)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        )
                      else if (_loadError != null)
                        Text(
                          '加载失败：$_loadError',
                          style: TextStyle(fontSize: 13, color: color.error),
                        )
                      else if (addableModels.isEmpty)
                        Text(
                          '暂无可添加模型',
                          style: TextStyle(fontSize: 13, color: color.outline),
                        )
                      else
                        ...addableModels.map(
                          (model) => _buildFetchedModelListItem(
                            model: model,
                            backgroundColor: color.surfaceContainer,
                            onAdd: () => _upsertModel(model),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentModelListItem({
    required String model,
    required String? remark,
    required ModelFeatureOptions features,
    required Color backgroundColor,
    required VoidCallback onEditRemark,
    required ValueChanged<bool> onToggleVision,
    required ValueChanged<bool> onToggleTools,
    required VoidCallback onRemove,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message:
                  model +
                  (remark == null || remark.isEmpty ? '' : '\n备注: $remark'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          model,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildCapabilityToggleIcon(
                        selected: features.supportsVision,
                        tooltip: '支持视觉',
                        icon: Icons.visibility_outlined,
                        onTap: () => onToggleVision(!features.supportsVision),
                      ),
                      const SizedBox(width: 4),
                      _buildCapabilityToggleIcon(
                        selected: features.supportsTools,
                        tooltip: '支持工具',
                        icon: Icons.build_outlined,
                        onTap: () => onToggleTools(!features.supportsTools),
                      ),
                    ],
                  ),
                  if (remark != null && remark.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '备注: ${remark.trim()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 20,
            height: 20,
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: '编辑模型信息',
              icon: Icon(Icons.edit_outlined, size: 17, color: colors.primary),
              onPressed: onEditRemark,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 20,
            height: 20,
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: '移除模型',
              icon: Icon(
                Icons.remove_circle_outline,
                size: 18,
                color: colors.error,
              ),
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapabilityToggleIcon({
    required bool selected,
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color:
            selected
                ? colors.primaryContainer.withAlpha(180)
                : colors.surfaceContainerHighest.withAlpha(160),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 24,
            height: 24,
            child: Icon(
              icon,
              size: 14,
              color:
                  selected
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFetchedModelListItem({
    required String model,
    required Color backgroundColor,
    required VoidCallback onAdd,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: model,
              child: Text(
                model,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: colors.onSurface),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 20,
            height: 20,
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: '添加模型',
              icon: Icon(
                Icons.add_circle_outline,
                size: 18,
                color: colors.primary,
              ),
              onPressed: onAdd,
            ),
          ),
        ],
      ),
    );
  }
}
