import 'package:flutter/material.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:now_chat/ui/widgets/select_model_list_item.dart';
import 'package:provider/provider.dart';

import '../../core/models/ai_provider_config.dart';

class ModelSelectorBottomSheet extends StatelessWidget {
  final void Function(String, String) onModelSelected;
  final String? model;
  final String? providerId;

  const ModelSelectorBottomSheet({super.key, required this.onModelSelected, required this.model, required this.providerId, });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final chatProvider = context.watch<ChatProvider>();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            //顶部拖拽条
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 3),
              decoration: BoxDecoration(
                color: color.outlineVariant,
                borderRadius: BorderRadius.circular(2)
              ),
            ),
          Column(
          mainAxisSize: MainAxisSize.min, 
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "选择模型",
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ...chatProvider.providers.map((provider) => SelectModelListItem(
              providerId: providerId,
              model: model,
              provider: provider,
              onSelect: (String model) {
                onModelSelected(provider.id, model);
              },
            )
            ),
          ],
        ),
          ],
        ),
      ),
    );
  }
}
