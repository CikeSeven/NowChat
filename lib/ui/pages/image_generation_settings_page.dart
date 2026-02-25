import 'package:flutter/material.dart';
import 'package:now_chat/core/models/ai_provider_config.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:now_chat/providers/settings_provider.dart';
import 'package:now_chat/ui/widgets/model_selector_bottom_sheet.dart.dart';
import 'package:provider/provider.dart';

/// 生图配置页面：
/// - 默认生图模型
/// - 默认图片编辑模型
/// - 是否向聊天模型暴露生图工具
class ImageGenerationSettingsPage extends StatelessWidget {
  const ImageGenerationSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final chatProvider = context.watch<ChatProvider>();
    final genProvider =
        (settings.defaultImageGenerationProviderId ?? '').isEmpty
            ? null
            : chatProvider.getProviderById(settings.defaultImageGenerationProviderId!);
    final editProvider =
        (settings.defaultImageEditProviderId ?? '').isEmpty
            ? null
            : chatProvider.getProviderById(settings.defaultImageEditProviderId!);
    final genDisplay = _buildModelDisplay(
      provider: genProvider,
      model: settings.defaultImageGenerationModel,
    );
    final editDisplay = _buildModelDisplay(
      provider: editProvider,
      model: settings.defaultImageEditModel,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('生图设置')),
      body: ListView(
        children: [
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: const Text('向聊天模型暴露生图工具'),
            subtitle: const Text('开启后聊天模型可调用“生图/图片编辑”工具'),
            value: settings.exposeImageToolsToChat,
            onChanged: (value) async {
              await context.read<SettingsProvider>().setExposeImageToolsToChat(
                value,
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('默认生图模型'),
            subtitle: Text(genDisplay),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (settings.defaultImageGenerationModel != null)
                  IconButton(
                    tooltip: '清除',
                    onPressed: () async {
                      await context
                          .read<SettingsProvider>()
                          .setDefaultImageGenerationModel(
                            providerId: null,
                            model: null,
                          );
                    },
                    icon: const Icon(Icons.clear_rounded),
                  ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
            onTap: () {
              _showModelSelector(
                context,
                allowedTypes: const {ModelType.imageGeneration},
                providerId: settings.defaultImageGenerationProviderId,
                model: settings.defaultImageGenerationModel,
                onSelected: (providerId, model) async {
                  await context.read<SettingsProvider>().setDefaultImageGenerationModel(
                    providerId: providerId,
                    model: model,
                  );
                },
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.auto_fix_high_outlined),
            title: const Text('默认图片编辑模型'),
            subtitle: Text(editDisplay),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (settings.defaultImageEditModel != null)
                  IconButton(
                    tooltip: '清除',
                    onPressed: () async {
                      await context.read<SettingsProvider>().setDefaultImageEditModel(
                        providerId: null,
                        model: null,
                      );
                    },
                    icon: const Icon(Icons.clear_rounded),
                  ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
            onTap: () {
              _showModelSelector(
                context,
                allowedTypes: const {ModelType.imageEdit},
                providerId: settings.defaultImageEditProviderId,
                model: settings.defaultImageEditModel,
                onSelected: (providerId, model) async {
                  await context.read<SettingsProvider>().setDefaultImageEditModel(
                    providerId: providerId,
                    model: model,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  /// 统一显示模型文本，避免页面出现空字符串。
  String _buildModelDisplay({
    required AIProviderConfig? provider,
    required String? model,
  }) {
    final normalizedModel = (model ?? '').trim();
    if (provider == null || normalizedModel.isEmpty) return '未设置';
    return '${provider.name} · ${provider.displayNameForModel(normalizedModel)}';
  }

  /// 弹出模型选择器并在选择后回传。
  void _showModelSelector(
    BuildContext context, {
    required Set<ModelType> allowedTypes,
    required String? providerId,
    required String? model,
    required Future<void> Function(String providerId, String model) onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      isDismissible: true,
      enableDrag: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      builder: (sheetContext) {
        return ModelSelectorBottomSheet(
          providerId: providerId,
          model: model,
          allowedModelTypes: allowedTypes,
          onModelSelected: (nextProviderId, nextModel) async {
            Navigator.of(sheetContext).pop();
            await onSelected(nextProviderId, nextModel);
          },
        );
      },
    );
  }
}
