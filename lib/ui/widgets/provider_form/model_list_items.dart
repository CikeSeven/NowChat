import 'package:flutter/material.dart';
import 'package:now_chat/core/models/ai_provider_config.dart';

/// CurrentModelListItem 类型定义。
class CurrentModelListItem extends StatelessWidget {
  final String model;
  final String? remark;
  final ModelFeatureOptions features;
  final Color backgroundColor;
  final VoidCallback onEditRemark;
  final ValueChanged<bool> onToggleVision;
  final ValueChanged<bool> onToggleTools;
  final VoidCallback onRemove;

  const CurrentModelListItem({
    super.key,
    required this.model,
    required this.remark,
    required this.features,
    required this.backgroundColor,
    required this.onEditRemark,
    required this.onToggleVision,
    required this.onToggleTools,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
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
                  (remark == null || remark!.isEmpty ? '' : '\n备注: $remark'),
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
                      _CapabilityToggleIcon(
                        selected: features.supportsVision,
                        tooltip: '支持视觉',
                        icon: Icons.visibility_outlined,
                        onTap: () => onToggleVision(!features.supportsVision),
                      ),
                      const SizedBox(width: 4),
                      _CapabilityToggleIcon(
                        selected: features.supportsTools,
                        tooltip: '支持工具',
                        icon: Icons.build_outlined,
                        onTap: () => onToggleTools(!features.supportsTools),
                      ),
                    ],
                  ),
                  if (remark != null && remark!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '备注: ${remark!.trim()}',
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
}

/// FetchedModelListItem 类型定义。
class FetchedModelListItem extends StatelessWidget {
  final String model;
  final Color backgroundColor;
  final VoidCallback onAdd;

  const FetchedModelListItem({
    super.key,
    required this.model,
    required this.backgroundColor,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
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

/// _CapabilityToggleIcon 类型定义。
class _CapabilityToggleIcon extends StatelessWidget {
  final bool selected;
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  const _CapabilityToggleIcon({
    required this.selected,
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 使用统一“选中/未选中”背景，保证能力开关状态一眼可见。
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
}
