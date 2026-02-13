import 'package:flutter/material.dart';
import 'package:now_chat/app/router.dart';
import 'package:now_chat/core/models/ai_provider_config.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:provider/provider.dart';

class ApiPage extends StatefulWidget {
  const ApiPage({super.key});

  @override
  State<ApiPage> createState() => _ApiPageState();
}

class _ApiPageState extends State<ApiPage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expandedProviderIds = <String>{};
  final Set<String> _expandedModelProviderIds = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleProviderExpanded(String providerId) {
    setState(() {
      if (_expandedProviderIds.contains(providerId)) {
        _expandedProviderIds.remove(providerId);
      } else {
        _expandedProviderIds.add(providerId);
      }
    });
  }

  void _toggleModelExpanded(String providerId) {
    setState(() {
      if (_expandedModelProviderIds.contains(providerId)) {
        _expandedModelProviderIds.remove(providerId);
      } else {
        _expandedModelProviderIds.add(providerId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final providers = chatProvider.providers;
    final colors = Theme.of(context).colorScheme;
    final query = _searchController.text.trim().toLowerCase();

    final filteredProviders =
        providers.where((provider) {
          final name = provider.name.toLowerCase();
          final type = provider.type.defaultName.toLowerCase();
          final baseUrl = (provider.baseUrl ?? '').toLowerCase();
          final hasRemarkMatch = provider.modelRemarks.values.any(
            (remark) => remark.toLowerCase().contains(query),
          );
          return name.contains(query) ||
              type.contains(query) ||
              baseUrl.contains(query) ||
              hasRemarkMatch;
        }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('API 管理')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索 API 名称、类型或地址',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon:
                    _searchController.text.isEmpty
                        ? null
                        : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child:
                providers.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.hub_outlined,
                            size: 34,
                            color: colors.outline,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '还没有 API 配置',
                            style: TextStyle(
                              fontSize: 15,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '点击右下角添加第一个提供方',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.outline,
                            ),
                          ),
                        ],
                      ),
                    )
                    : filteredProviders.isEmpty
                    ? Center(
                      child: Text(
                        '没有匹配的 API',
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    )
                    : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 90),
                      itemCount: filteredProviders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final provider = filteredProviders[index];
                        final isExpanded = _expandedProviderIds.contains(
                          provider.id,
                        );
                        final isModelExpanded = _expandedModelProviderIds
                            .contains(provider.id);
                        return _ApiProviderCard(
                          provider: provider,
                          isExpanded: isExpanded,
                          isModelListExpanded: isModelExpanded,
                          onToggleExpand:
                              () => _toggleProviderExpanded(provider.id),
                          onToggleModelList:
                              () => _toggleModelExpanded(provider.id),
                          onEdit: () {
                            Navigator.pushNamed(
                              context,
                              AppRoutes.providerForm,
                              arguments: {
                                'mode': 'edit',
                                'providerId': provider.id,
                              },
                            );
                          },
                          onDelete:
                              () => _confirmDelete(provider.id, provider.name),
                        );
                      },
                    ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.pushNamed(
            context,
            AppRoutes.providerForm,
            arguments: const {'mode': 'create'},
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('添加 API'),
      ),
    );
  }

  Future<void> _confirmDelete(String providerId, String name) async {
    final color = Theme.of(context).colorScheme;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            backgroundColor: color.surfaceContainerLow,
            title: Text('删除 API', style: TextStyle(color: color.onSurface)),
            content: Text(
              '确认删除 "$name" 吗？该操作不可恢复。',
              style: TextStyle(color: color.onSurfaceVariant),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(
                  '取消',
                  style: TextStyle(color: color.onSurfaceVariant),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text('删除', style: TextStyle(color: color.error)),
              ),
            ],
          ),
    );

    if (shouldDelete == true) {
      if (!mounted) return;
      await context.read<ChatProvider>().deleteProvider(providerId);
    }
  }
}

class _ApiProviderCard extends StatelessWidget {
  final AIProviderConfig provider;
  final bool isExpanded;
  final bool isModelListExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onToggleModelList;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ApiProviderCard({
    required this.provider,
    required this.isExpanded,
    required this.isModelListExpanded,
    required this.onToggleExpand,
    required this.onToggleModelList,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final models = provider.models;
    final baseUrl = (provider.baseUrl ?? '').trim();
    final requestPath = (provider.urlPath ?? '').trim();
    final baseUrlText = baseUrl.isEmpty ? '-' : baseUrl;
    final requestPathText = requestPath.isEmpty ? '-' : requestPath;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Card(
        elevation: 0,
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            provider.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Tooltip(
                            message: baseUrlText,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.link_rounded,
                                  size: 14,
                                  color: colors.onSurfaceVariant,
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    baseUrlText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.end,
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
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  _buildActionIcon(
                    context: context,
                    icon: Icons.edit_outlined,
                    tooltip: '编辑 API',
                    color: colors.primary,
                    onTap: onEdit,
                  ),
                  const SizedBox(width: 4),
                  _buildActionIcon(
                    context: context,
                    icon: Icons.delete_outline,
                    tooltip: '删除 API',
                    color: colors.error,
                    onTap: onDelete,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildTag(context, provider.type.defaultName),
                  _buildTag(context, provider.requestMode.label),
                  _buildTag(context, '${models.length} 个模型'),
                ],
              ),
              const SizedBox(height: 6),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onToggleExpand,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 2,
                    horizontal: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isExpanded ? '收起详情' : '查看更多',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: colors.primary,
                      ),
                    ],
                  ),
                ),
              ),
              if (isExpanded) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainer.withAlpha(140),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.outline.withAlpha(70)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '请求路径: $requestPathText',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            '模型列表',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 0,
                              ),
                              minimumSize: const Size(0, 26),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: onToggleModelList,
                            icon: Icon(
                              isModelListExpanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              size: 16,
                            ),
                            label: Text(
                              isModelListExpanded ? '收起' : '展开',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      if (models.isEmpty)
                        Text(
                          '暂无模型',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        )
                      else if (!isModelListExpanded)
                        Text(
                          '已收起，点击“展开”查看全部模型',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        )
                      else
                        ...models.map(
                          (model) => _buildModelItem(context, model: model),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionIcon({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 26,
        height: 26,
        child: IconButton(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 26, height: 26),
          icon: Icon(icon, size: 17, color: color),
          onPressed: onTap,
        ),
      ),
    );
  }

  Widget _buildModelItem(BuildContext context, {required String model}) {
    final colors = Theme.of(context).colorScheme;
    final displayName = provider.displayNameForModel(model);
    final features = provider.featuresForModel(model);
    final hasRemark = displayName.trim() != model.trim();

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface.withAlpha(180),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outline.withAlpha(90)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.8,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
                if (hasRemark) ...[
                  const SizedBox(height: 2),
                  Text(
                    model,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (features.supportsVision)
                _buildCapabilityPill(
                  context,
                  icon: Icons.visibility_outlined,
                  tooltip: '支持视觉',
                ),
              if (features.supportsVision && features.supportsTools)
                const SizedBox(width: 4),
              if (features.supportsTools)
                _buildCapabilityPill(
                  context,
                  icon: Icons.build_outlined,
                  tooltip: '支持工具',
                ),
              if (!features.hasAnyCapability)
                Text(
                  '基础',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCapabilityPill(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: colors.secondaryContainer.withAlpha(190),
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 13, color: colors.onSecondaryContainer),
      ),
    );
  }

  Widget _buildTag(BuildContext context, String text) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withAlpha(130),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.2,
          color: colors.onPrimaryContainer,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
