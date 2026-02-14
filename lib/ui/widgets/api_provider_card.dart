import 'package:flutter/material.dart';
import 'package:now_chat/core/models/ai_provider_config.dart';

class ApiProviderCard extends StatelessWidget {
  final AIProviderConfig provider;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const ApiProviderCard({
    super.key,
    required this.provider,
    required this.isExpanded,
    required this.onToggleExpand,
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
