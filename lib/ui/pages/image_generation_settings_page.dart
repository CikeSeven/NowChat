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
/// - 默认图片尺寸
/// - 队列并发数
class ImageGenerationSettingsPage extends StatelessWidget {
  const ImageGenerationSettingsPage({super.key});

  static const List<String> _sizeOptions = <String>[
    '512x512',
    '768x768',
    '1024x1024',
    '1024x1536',
    '1536x1024',
    '2048x2048',
  ];

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
            subtitle: const Text('开启后聊天模型调用工具会将任务加入生图队列，不等待生成完成'),
            value: settings.exposeImageToolsToChat,
            onChanged: (value) async {
              await context.read<SettingsProvider>().setExposeImageToolsToChat(
                value,
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.photo_size_select_large_outlined),
            title: const Text('默认生图尺寸'),
            subtitle: Text(settings.defaultImageGenerateSize),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              _showSizeSelector(
                context,
                title: '选择默认生图尺寸',
                currentValue: settings.defaultImageGenerateSize,
                onSelected: (size) async {
                  await context.read<SettingsProvider>().setDefaultImageGenerateSize(size);
                },
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.crop_outlined),
            title: const Text('默认编辑尺寸'),
            subtitle: Text(settings.defaultImageEditSize),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              _showSizeSelector(
                context,
                title: '选择默认编辑尺寸',
                currentValue: settings.defaultImageEditSize,
                onSelected: (size) async {
                  await context.read<SettingsProvider>().setDefaultImageEditSize(size);
                },
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.queue_outlined),
            title: const Text('队列并发数'),
            subtitle: Text(
              '${settings.imageQueueConcurrency}（同时执行任务数）',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              _showConcurrencySelector(
                context,
                currentValue: settings.imageQueueConcurrency,
                onSelected: (value) async {
                  await context.read<SettingsProvider>().setImageQueueConcurrency(value);
                },
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

  /// 选择默认尺寸。
  void _showSizeSelector(
    BuildContext context, {
    required String title,
    required String currentValue,
    required Future<void> Function(String value) onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(title),
                dense: true,
                enabled: false,
              ),
              for (final size in _sizeOptions)
                ListTile(
                  title: Text(size),
                  trailing:
                      size == currentValue
                          ? Icon(
                            Icons.check_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          )
                          : null,
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await onSelected(size);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  /// 选择队列并发数（1~4）。
  void _showConcurrencySelector(
    BuildContext context, {
    required int currentValue,
    required Future<void> Function(int value) onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text('选择并发数'),
                subtitle: Text('并发越高，速度越快，但更占用网络和设备资源'),
                dense: true,
                enabled: false,
              ),
              for (final value in <int>[1, 2, 3, 4])
                ListTile(
                  title: Text('$value'),
                  trailing:
                      value == currentValue
                          ? Icon(
                            Icons.check_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          )
                          : null,
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await onSelected(value);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
