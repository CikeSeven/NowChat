import 'package:flutter/material.dart';
import 'package:now_chat/core/models/ai_provider_config.dart';
import 'package:now_chat/core/provider/provider_catalog.dart';
import 'package:now_chat/ui/widgets/provider_form/model_list_items.dart';

/// ProviderCatalogSection 类型定义。
class ProviderCatalogSection extends StatelessWidget {
  final TextEditingController searchController;
  final List<ProviderPreset> filteredPresets;
  final List<ProviderPreset> visiblePresets;
  final bool isSearching;
  final bool showAllPresets;
  final int collapsedPresetCount;
  final String selectedPresetId;
  final String selectedPresetDescription;
  final VoidCallback onSearchChanged;
  final ValueChanged<String> onSelectPreset;
  final VoidCallback onToggleShowAll;

  const ProviderCatalogSection({
    super.key,
    required this.searchController,
    required this.filteredPresets,
    required this.visiblePresets,
    required this.isSearching,
    required this.showAllPresets,
    required this.collapsedPresetCount,
    required this.selectedPresetId,
    required this.selectedPresetDescription,
    required this.onSearchChanged,
    required this.onSelectPreset,
    required this.onToggleShowAll,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Card(
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
              controller: searchController,
              onChanged: (_) => onSearchChanged(),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '搜索提供方（例如 OpenAI / Gemini）',
                prefixIcon: Icon(Icons.search, size: 18),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            // 提供方预设快速选择区。
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children:
                  visiblePresets.map((preset) {
                    return ChoiceChip(
                      label: Text(preset.name),
                      selected: selectedPresetId == preset.id,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      onSelected: (_) => onSelectPreset(preset.id),
                    );
                  }).toList(),
            ),
            if (!isSearching && filteredPresets.length > collapsedPresetCount) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onToggleShowAll,
                  icon: Icon(
                    showAllPresets
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                  ),
                  label: Text(
                    showAllPresets
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
              selectedPresetDescription,
              style: TextStyle(fontSize: 12, color: color.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// ProviderConnectionSection 类型定义。
class ProviderConnectionSection extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController baseUrlController;
  final TextEditingController pathController;
  final TextEditingController apiKeyController;
  final RequestMode selectedRequestMode;
  final ProviderType selectedType;
  final bool keyObscure;
  final String previewEndpoint;
  final VoidCallback onChanged;
  final ValueChanged<RequestMode> onRequestModeChanged;
  final VoidCallback onToggleObscure;

  const ProviderConnectionSection({
    super.key,
    required this.nameController,
    required this.baseUrlController,
    required this.pathController,
    required this.apiKeyController,
    required this.selectedRequestMode,
    required this.selectedType,
    required this.keyObscure,
    required this.previewEndpoint,
    required this.onChanged,
    required this.onRequestModeChanged,
    required this.onToggleObscure,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Card(
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
              controller: nameController,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'API 名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            // 请求方式会决定协议类型与默认路径策略。
            DropdownButtonFormField<RequestMode>(
              value: selectedRequestMode,
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
                onRequestModeChanged(mode);
              },
              decoration: const InputDecoration(
                isDense: true,
                labelText: '请求方式',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              selectedRequestMode.supportsStreaming
                  ? '当前请求方式支持流式输出'
                  : '当前请求方式暂不支持流式输出，将自动回退普通请求',
              style: TextStyle(fontSize: 12, color: color.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: baseUrlController,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Base URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: pathController,
              onChanged: (_) => onChanged(),
              readOnly: !selectedType.allowEditPath,
              decoration: InputDecoration(
                isDense: true,
                labelText: '请求路径',
                border: const OutlineInputBorder(),
                helperText: selectedType.allowEditPath ? null : '当前协议为固定路径',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: apiKeyController,
              obscureText: keyObscure,
              decoration: InputDecoration(
                isDense: true,
                labelText: 'API Key',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    keyObscure ? Icons.visibility_off : Icons.visibility,
                    size: 18,
                  ),
                  onPressed: onToggleObscure,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '预览：$previewEndpoint',
              style: TextStyle(fontSize: 12, color: color.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// ProviderModelsSection 类型定义。
class ProviderModelsSection extends StatelessWidget {
  final List<String> models;
  final Map<String, String> modelRemarks;
  final Map<String, ModelFeatureOptions> modelCapabilities;
  final bool loadingModels;
  final bool canFetchModels;
  final VoidCallback onAddCustomModel;
  final VoidCallback onFetchModels;
  final void Function(String model) onEditModel;
  final void Function(String model, bool enabled) onToggleVision;
  final void Function(String model, bool enabled) onToggleTools;
  final void Function(String model) onRemoveModel;

  const ProviderModelsSection({
    super.key,
    required this.models,
    required this.modelRemarks,
    required this.modelCapabilities,
    required this.loadingModels,
    required this.canFetchModels,
    required this.onAddCustomModel,
    required this.onFetchModels,
    required this.onEditModel,
    required this.onToggleVision,
    required this.onToggleTools,
    required this.onRemoveModel,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Card(
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
                      onPressed: onAddCustomModel,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('手动添加'),
                    ),
                    TextButton.icon(
                      onPressed: canFetchModels ? onFetchModels : null,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(loadingModels ? '获取中...' : '获取模型'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '当前模型',
              style: TextStyle(fontSize: 13, color: color.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            if (models.isEmpty)
              Text('暂无模型', style: TextStyle(fontSize: 13, color: color.outline))
            else
              ...models.map(
                (model) => CurrentModelListItem(
                  model: model,
                  remark: modelRemarks[model],
                  features:
                      modelCapabilities[model] ?? const ModelFeatureOptions(),
                  backgroundColor: color.primaryContainer.withAlpha(120),
                  onEditRemark: () => onEditModel(model),
                  onToggleVision: (enabled) => onToggleVision(model, enabled),
                  onToggleTools: (enabled) => onToggleTools(model, enabled),
                  onRemove: () => onRemoveModel(model),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// FetchedModelsSection 类型定义。
class FetchedModelsSection extends StatefulWidget {
  final bool loadingModels;
  final String? loadError;
  final List<String> addableModels;
  final void Function(String model) onAddModel;

  const FetchedModelsSection({
    super.key,
    required this.loadingModels,
    required this.loadError,
    required this.addableModels,
    required this.onAddModel,
  });

  @override
  State<FetchedModelsSection> createState() => _FetchedModelsSectionState();
}

/// _FetchedModelsSectionState 视图状态。
class _FetchedModelsSectionState extends State<FetchedModelsSection> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    // 搜索仅在可添加模型列表内过滤。
    final visibleModels =
        normalizedQuery.isEmpty
            ? widget.addableModels
            : widget.addableModels
                .where(
                  (model) => model.toLowerCase().contains(normalizedQuery),
                )
                .toList();

    return Card(
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
            TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索模型',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon:
                    _searchQuery.trim().isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清空',
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                            icon: const Icon(Icons.close, size: 16),
                          ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            if (widget.loadingModels)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              )
            else if (widget.loadError != null)
              Text(
                '加载失败：${widget.loadError}',
                style: TextStyle(fontSize: 13, color: color.error),
              )
            else if (widget.addableModels.isEmpty)
              Text(
                '暂无可添加模型',
                style: TextStyle(fontSize: 13, color: color.outline),
              )
            else if (visibleModels.isEmpty)
              Text(
                '没有匹配的模型',
                style: TextStyle(fontSize: 13, color: color.outline),
              )
            else
              ...visibleModels.map(
                (model) => FetchedModelListItem(
                  model: model,
                  backgroundColor: color.surfaceContainer,
                  onAdd: () => widget.onAddModel(model),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
