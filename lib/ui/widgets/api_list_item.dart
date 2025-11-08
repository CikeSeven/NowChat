import 'package:flutter/material.dart';
import 'package:now_chat/core/models/ai_provider_config.dart';

class ApiListItem extends StatefulWidget {
  final AIProviderConfig provider;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;

  const ApiListItem({
    super.key,
    required this.provider,
    this.onTap,
    this.onLongPress,
    this.onDelete,
  });

  @override
  State<ApiListItem> createState() => _ApiListItemState();
}

class _ApiListItemState extends State<ApiListItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final models = widget.provider.models;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 12),
      child: Material(
        color: color.primaryContainer.withAlpha(85),
        borderRadius: BorderRadius.circular(8),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                widget.onTap?.call();
              },
              onLongPress: widget.onLongPress,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    /// 第一行：名称 + 类型 + 删除图标 + 展开图标
                    Row(
                      children: [
                        // 左侧名称 + 类型
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${widget.provider.name} [${models.length}]",
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w500),
                              ),
                              Text(
                                widget.provider.type.defaultName,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: color.secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            _expanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 22,
                            color: color.secondary,
                          ),
                          onPressed: () => setState(() => _expanded = !_expanded),
                        ),
            
                        // 删除按钮
                        IconButton(
                          icon: Icon(Icons.delete_outline,
                              color: color.error, size: 20),
                          onPressed: widget.onDelete,
                        ),
                      ],
                    ),
            
                    
                  ],
                ),
              ),
            ),
            /// 动画展开部分
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
                child: Column(
                  children: [
                    models.isEmpty
                        ? Text(
                            "暂无模型",
                            style: TextStyle(
                              fontSize: 13,
                              color: color.onSurfaceVariant,
                            ),
                          )
                        : Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: models
                                .map(
                                  (model) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: color.surface,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: color.outline.withAlpha(80)),
                                    ),
                                    child: Text(
                                      model,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: color.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                  ],
                ),
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }
}
