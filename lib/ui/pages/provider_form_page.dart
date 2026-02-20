import 'dart:async';

import 'package:flutter/material.dart';
import 'package:now_chat/core/models/ai_provider_config.dart';
import 'package:now_chat/core/provider/provider_catalog.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:now_chat/ui/widgets/provider_form/custom_model_dialog.dart';
import 'package:now_chat/ui/widgets/provider_form/provider_form_sections.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

/// ProviderFormPage 页面。
class ProviderFormPage extends StatefulWidget {
  final String? providerId;

  const ProviderFormPage({super.key, this.providerId});

  @override
  State<ProviderFormPage> createState() => _ProviderFormPageState();
}

/// _ProviderFormPageState 视图状态。
class _ProviderFormPageState extends State<ProviderFormPage> {
  /// 预设卡片默认折叠显示数量，避免首屏列表过长。
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
  String? _activeProviderId;
  bool _isAutoSaving = false;
  bool _pendingAutoSave = false;
  bool _isDisposed = false;

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
        _activeProviderId = existing.id;
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
    _isDisposed = true;
    _nameController.dispose();
    _baseUrlController.dispose();
    _pathController.dispose();
    _apiKeyController.dispose();
    _presetSearchController.dispose();
    super.dispose();
  }

  /// 在生命周期安全时标记“当前已进入编辑态”。
  ///
  /// 这里使用下一帧更新，避免在弹窗关闭/路由切换动画期间触发同步 setState。
  void _markEditingSaved(String providerId) {
    _isEditing = true;
    _activeProviderId = providerId;
    if (!mounted || _isDisposed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDisposed) return;
      setState(() {
        _isEditing = true;
        _activeProviderId = providerId;
      });
    });
  }

  /// 表单最小可保存条件。
  bool get _canSave {
    return _nameController.text.trim().isNotEmpty &&
        _baseUrlController.text.trim().isNotEmpty &&
        _pathController.text.trim().isNotEmpty;
  }

  /// 将当前表单值组装为 Provider 配置对象。
  AIProviderConfig _buildPayload(String providerId) {
    return AIProviderConfig(
      id: providerId,
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
  }

  /// 持久化当前配置（新建或更新）。
  Future<bool> _persistCurrentProvider() async {
    if (!_canSave || !mounted || _isDisposed) return false;

    final chatProvider = context.read<ChatProvider>();
    final providerId = _activeProviderId ?? const Uuid().v4();
    final payload = _buildPayload(providerId);
    final exists = chatProvider.getProviderById(providerId) != null;

    if (exists) {
      await chatProvider.updateProvider(
        providerId,
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
    if (_isDisposed) return false;
    if (!_isEditing || _activeProviderId != providerId) {
      _markEditingSaved(providerId);
    }
    return true;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    while (_isAutoSaving) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    final saved = await _persistCurrentProvider();
    if (!saved || !mounted) return;
    Navigator.of(context).pop();
  }

  /// 触发自动保存（带并发合并）。
  ///
  /// 若已有保存在执行，则只置位 `_pendingAutoSave`，完成后再补一次。
  void _scheduleAutoSave() {
    if (_isDisposed || !mounted || !_canSave) return;
    if (_isAutoSaving) {
      _pendingAutoSave = true;
      return;
    }
    _isAutoSaving = true;
    unawaited(_runAutoSave());
  }

  /// 自动保存实际执行函数。
  Future<void> _runAutoSave() async {
    if (_isDisposed || !mounted) {
      _isAutoSaving = false;
      _pendingAutoSave = false;
      return;
    }
    try {
      await _persistCurrentProvider();
    } catch (_) {
      // 自动保存失败不打断当前交互，用户仍可手动点击保存重试
    } finally {
      if (_isDisposed) {
        _isAutoSaving = false;
        _pendingAutoSave = false;
      }
      _isAutoSaving = false;
      if (_pendingAutoSave) {
        _pendingAutoSave = false;
        _scheduleAutoSave();
      }
    }
  }

  /// 选择预设后应用默认配置。
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

  /// 由请求模式推导 ProviderType，保证协议语义一致。
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

  /// 切换请求模式后，按需同步 path/baseUrl 默认值。
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

  /// 新增或更新模型元信息（备注、能力开关）。
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
    _scheduleAutoSave();
  }

  /// 删除模型及其附属元信息。
  void _removeModel(String model) {
    setState(() {
      _models.remove(model);
      _modelRemarks.remove(model);
      _modelCapabilities.remove(model);
    });
    _scheduleAutoSave();
  }

  /// 切换模型能力标签（视觉/工具）。
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
    _scheduleAutoSave();
  }

  /// 打开自定义模型弹窗（可用于新增或编辑）。
  Future<void> _showCustomModelDialog({
    String? initialModel,
    String? initialRemark,
    ModelFeatureOptions? initialFeatures,
    bool lockModelName = false,
  }) async {
    final result = await showCustomModelDialog(
      context: context,
      existingModels: _models.toSet(),
      initialModel: initialModel,
      initialRemark: initialRemark,
      initialFeatures: initialFeatures,
      lockModelName: lockModelName,
    );
    if (!mounted || _isDisposed || result == null) return;
    _upsertModel(
      result.model,
      remark: result.remark,
      supportsVision: result.supportsVision,
      supportsTools: result.supportsTools,
    );
  }

  /// 远端拉取模型列表并写入“可添加模型”区域。
  Future<void> _fetchModels() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    if (baseUrl.isEmpty) return;
    _scheduleAutoSave();

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
            ProviderCatalogSection(
              searchController: _presetSearchController,
              filteredPresets: filteredPresets,
              visiblePresets: visiblePresets,
              isSearching: isSearchingPresets,
              showAllPresets: _showAllPresets,
              collapsedPresetCount: _collapsedPresetCount,
              selectedPresetId: _selectedPresetId,
              selectedPresetDescription:
                  ProviderCatalog.findById(_selectedPresetId).description,
              onSearchChanged: () => setState(() {}),
              onSelectPreset: _onSelectPreset,
              onToggleShowAll: () {
                setState(() {
                  _showAllPresets = !_showAllPresets;
                });
              },
            ),
            const SizedBox(height: 12),
            ProviderConnectionSection(
              nameController: _nameController,
              baseUrlController: _baseUrlController,
              pathController: _pathController,
              apiKeyController: _apiKeyController,
              selectedRequestMode: _selectedRequestMode,
              selectedType: _selectedType,
              keyObscure: _keyObscure,
              previewEndpoint:
                  '${_baseUrlController.text.trim()}${_pathController.text.trim()}',
              onChanged: () => setState(() {}),
              onRequestModeChanged: _onRequestModeChanged,
              onToggleObscure: () {
                setState(() {
                  _keyObscure = !_keyObscure;
                });
              },
            ),
            const SizedBox(height: 12),
            ProviderModelsSection(
              models: _models,
              modelRemarks: _modelRemarks,
              modelCapabilities: _modelCapabilities,
              loadingModels: _loadingModels,
              canFetchModels: canFetchModels,
              onAddCustomModel: () {
                _showCustomModelDialog();
              },
              onFetchModels: () {
                _fetchModels();
              },
              onEditModel: (model) {
                _showCustomModelDialog(
                  initialModel: model,
                  initialRemark: _modelRemarks[model],
                  initialFeatures: _modelCapabilities[model],
                  lockModelName: true,
                );
              },
              onToggleVision:
                  (model, enabled) =>
                      _toggleModelCapability(model, supportsVision: enabled),
              onToggleTools:
                  (model, enabled) =>
                      _toggleModelCapability(model, supportsTools: enabled),
              onRemoveModel: _removeModel,
            ),
            if (_loadingModels ||
                _loadError != null ||
                _fetchedModels.isNotEmpty) ...[
              const SizedBox(height: 12),
              FetchedModelsSection(
                loadingModels: _loadingModels,
                loadError: _loadError,
                addableModels: addableModels,
                onAddModel: _upsertModel,
              ),
            ],
          ],
        ),
      ),
    );
  }

}
