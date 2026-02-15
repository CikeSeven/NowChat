import 'package:flutter/material.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:provider/provider.dart';

/// 模型选择弹窗：支持按提供方筛选与关键词搜索。
class ModelSelectorBottomSheet extends StatefulWidget {
  final void Function(String, String) onModelSelected;
  final String? model;
  final String? providerId;

  const ModelSelectorBottomSheet({
    super.key,
    required this.onModelSelected,
    required this.model,
    required this.providerId,
  });

  @override
  State<ModelSelectorBottomSheet> createState() => _ModelSelectorBottomSheetState();
}

class _ModelSelectorBottomSheetState extends State<ModelSelectorBottomSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _activeProviderId;

  @override
  void initState() {
    super.initState();
    _activeProviderId = widget.providerId;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final chatProvider = context.watch<ChatProvider>();
    final providers = chatProvider.providers;

    if (providers.isEmpty) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: color.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Text(
                '暂无可选模型',
                style: TextStyle(fontSize: 14, color: color.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final normalizedQuery = _query.trim().toLowerCase();
    final activeProviderId =
        _activeProviderId != null &&
            providers.any((provider) => provider.id == _activeProviderId)
        ? _activeProviderId
        : providers.first.id;
    final activeProvider = providers.firstWhere(
      (provider) => provider.id == activeProviderId,
    );

    final modelsForActiveProvider = activeProvider.models.where((model) {
      if (normalizedQuery.isEmpty) return true;
      final display = activeProvider.displayNameForModel(model).toLowerCase();
      final raw = model.toLowerCase();
      final providerName = activeProvider.name.toLowerCase();
      return display.contains(normalizedQuery) ||
          raw.contains(normalizedQuery) ||
          providerName.contains(normalizedQuery);
    }).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: color.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Row(
              children: [
                Text('选择模型', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _query = value;
                });
              },
              decoration: InputDecoration(
                hintText: '搜索提供方或模型',
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _query.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _query = '';
                          });
                        },
                        icon: const Icon(Icons.close_rounded, size: 16),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: providers.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final provider = providers[index];
                  final selected = provider.id == activeProviderId;
                  return ChoiceChip(
                    selected: selected,
                    label: Text('${provider.name} ${provider.models.length}'),
                    onSelected: (_) {
                      setState(() {
                        _activeProviderId = provider.id;
                      });
                    },
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: modelsForActiveProvider.isEmpty
                  ? Center(
                      child: Text(
                        '没有匹配的模型',
                        style: TextStyle(
                          fontSize: 13,
                          color: color.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: modelsForActiveProvider.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final rawModel = modelsForActiveProvider[index];
                        final displayModel = activeProvider.displayNameForModel(
                          rawModel,
                        );
                        final isSelected =
                            activeProvider.id == widget.providerId &&
                            rawModel == widget.model;
                        final features = activeProvider.featuresForModel(
                          rawModel,
                        );
                        return Material(
                          color: isSelected
                              ? color.primaryContainer.withAlpha(95)
                              : color.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () =>
                                widget.onModelSelected(activeProvider.id, rawModel),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          displayModel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: color.onSurface,
                                          ),
                                        ),
                                        if (displayModel != rawModel) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            rawModel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              color: color.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (features.supportsVision)
                                    _capabilityIcon(
                                      context,
                                      icon: Icons.visibility_outlined,
                                      tooltip: '支持视觉',
                                    ),
                                  if (features.supportsVision &&
                                      features.supportsTools)
                                    const SizedBox(width: 6),
                                  if (features.supportsTools)
                                    _capabilityIcon(
                                      context,
                                      icon: Icons.build_outlined,
                                      tooltip: '支持工具',
                                    ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    isSelected
                                        ? Icons.check_circle_rounded
                                        : Icons.chevron_right_rounded,
                                    size: 18,
                                    color: isSelected
                                        ? color.primary
                                        : color.onSurfaceVariant,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _capabilityIcon(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
  }) {
    final color = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: color.secondaryContainer.withAlpha(180),
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 12, color: color.onSecondaryContainer),
      ),
    );
  }
}
