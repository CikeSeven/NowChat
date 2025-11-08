import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import '../../core/models/ai_provider_config.dart';

class SelectModelListItem extends StatefulWidget {
  final AIProviderConfig provider;
  final ValueChanged<String> onSelect;
  final String? providerId;
  final String? model;
  const SelectModelListItem({super.key, required this.provider, required this.onSelect, required this.providerId, required this.model});
  @override
  State<SelectModelListItem> createState() => _SelectModelListItemState();
}

class _SelectModelListItemState extends State<SelectModelListItem> {
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
                setState(() => _expanded = !_expanded);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${widget.provider.name} [${widget.provider.models.length}]",
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                         Icon(
                            _expanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 22,
                            color: color.secondary,
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
                    Divider(),
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
                                  (model) => InkWell(
                                    onTap: () {
                                      widget.onSelect(model);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: (widget.providerId == widget.provider.id
                                                && widget.model == model) ? color.primaryContainer : color.surface,
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