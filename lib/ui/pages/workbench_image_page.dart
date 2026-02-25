import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:now_chat/core/models/ai_provider_config.dart';
import 'package:now_chat/core/models/image_generation_record.dart';
import 'package:now_chat/core/network/api_service.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:now_chat/providers/settings_provider.dart';
import 'package:now_chat/ui/pages/image_preview_page.dart';
import 'package:now_chat/ui/widgets/model_selector_bottom_sheet.dart.dart';
import 'package:now_chat/util/storage.dart';
import 'package:provider/provider.dart';

enum _ImageWorkbenchMode { generate, edit }

/// 工作台生图页（独立历史，不写入聊天会话）。
class WorkbenchImagePage extends StatefulWidget {
  const WorkbenchImagePage({super.key});

  @override
  State<WorkbenchImagePage> createState() => _WorkbenchImagePageState();
}

class _WorkbenchImagePageState extends State<WorkbenchImagePage> {
  final TextEditingController _promptController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  _ImageWorkbenchMode _mode = _ImageWorkbenchMode.generate;
  String? _providerId;
  String? _model;
  String? _sourceImagePath;
  bool _submitting = false;
  List<ImageGenerationRecord> _history = <ImageGenerationRecord>[];

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  /// 初始化默认模型与本地历史。
  Future<void> _loadInitialState() async {
    final settings = context.read<SettingsProvider>();
    final history = await Storage.loadImageGenerationHistory();
    if (!mounted) return;
    setState(() {
      _history = history..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
    _applyDefaultsFromSettings(settings);
  }

  /// 根据当前模式应用默认模型。
  void _applyDefaultsFromSettings(SettingsProvider settings) {
    if (_mode == _ImageWorkbenchMode.generate) {
      _providerId = settings.defaultImageGenerationProviderId;
      _model = settings.defaultImageGenerationModel;
      return;
    }
    _providerId = settings.defaultImageEditProviderId;
    _model = settings.defaultImageEditModel;
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final chatProvider = context.watch<ChatProvider>();
    final selectedProvider =
        (_providerId ?? '').isEmpty
            ? null
            : chatProvider.getProviderById(_providerId!);
    final selectedModel = (_model ?? '').trim();
    final hasModel = selectedProvider != null && selectedModel.isNotEmpty;
    final modelDisplay =
        hasModel
            ? '${selectedProvider.name} · ${selectedProvider.displayNameForModel(selectedModel)}'
            : '未设置';
    final currentModelType =
        hasModel
            ? selectedProvider.featuresForModel(selectedModel).modelType
            : null;
    final expectedModelType =
        _mode == _ImageWorkbenchMode.generate
            ? ModelType.imageGeneration
            : ModelType.imageEdit;
    final modelTypeMismatch =
        hasModel && currentModelType != null && currentModelType != expectedModelType;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<_ImageWorkbenchMode>(
                  segments: const [
                    ButtonSegment(
                      value: _ImageWorkbenchMode.generate,
                      icon: Icon(Icons.image_outlined),
                      label: Text('生图'),
                    ),
                    ButtonSegment(
                      value: _ImageWorkbenchMode.edit,
                      icon: Icon(Icons.auto_fix_high_outlined),
                      label: Text('图片编辑'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (value) {
                    setState(() {
                      _mode = value.first;
                      _sourceImagePath = null;
                      _applyDefaultsFromSettings(
                        context.read<SettingsProvider>(),
                      );
                    });
                  },
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.smart_toy_outlined),
                  title: const Text('模型'),
                  subtitle: Text(modelDisplay),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _openModelSelector,
                ),
                if (modelTypeMismatch)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '当前模型类型与模式不匹配，请重新选择模型',
                      style: TextStyle(color: color.error, fontSize: 12.5),
                    ),
                  ),
                TextField(
                  controller: _promptController,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    isDense: true,
                    labelText: _mode == _ImageWorkbenchMode.generate ? '生图提示词' : '编辑提示词',
                    hintText:
                        _mode == _ImageWorkbenchMode.generate
                            ? '例如：赛博朋克风格城市夜景，霓虹灯，电影感'
                            : '例如：把背景改为雪山，保留主体人物',
                  ),
                ),
                const SizedBox(height: 10),
                if (_mode == _ImageWorkbenchMode.edit) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _submitting ? null : _pickSourceImage,
                          icon: const Icon(Icons.upload_file_outlined),
                          label: Text(
                            _sourceImagePath == null ? '选择待编辑图片' : '重新选择图片',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_sourceImagePath != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(_sourceImagePath!),
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                ],
                FilledButton.icon(
                  onPressed:
                      _submitting || modelTypeMismatch || !hasModel
                          ? null
                          : _submit,
                  icon:
                      _submitting
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : Icon(
                            _mode == _ImageWorkbenchMode.generate
                                ? Icons.auto_awesome_outlined
                                : Icons.edit_note_outlined,
                          ),
                  label: Text(_submitting ? '处理中...' : '开始${_mode == _ImageWorkbenchMode.generate ? '生图' : '编辑'}'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '历史记录',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        if (_history.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                '暂无记录',
                style: TextStyle(color: color.onSurfaceVariant),
              ),
            ),
          )
        else
          ..._history.map((item) => _buildHistoryCard(context, item)),
      ],
    );
  }

  /// 打开模型选择器，仅展示当前模式对应的模型类型。
  void _openModelSelector() {
    final allowedType =
        _mode == _ImageWorkbenchMode.generate
            ? ModelType.imageGeneration
            : ModelType.imageEdit;
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
          providerId: _providerId,
          model: _model,
          allowedModelTypes: {allowedType},
          onModelSelected: (providerId, model) {
            Navigator.of(sheetContext).pop();
            setState(() {
              _providerId = providerId;
              _model = model;
            });
          },
        );
      },
    );
  }

  /// 选择图片编辑原图。
  Future<void> _pickSourceImage() async {
    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    setState(() {
      _sourceImagePath = image.path;
    });
  }

  /// 执行生图/图片编辑请求，并写入独立历史。
  Future<void> _submit() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      _showSnackBar('请输入提示词');
      return;
    }
    final chatProvider = context.read<ChatProvider>();
    final provider =
        (_providerId ?? '').isEmpty
            ? null
            : chatProvider.getProviderById(_providerId!);
    final model = (_model ?? '').trim();
    if (provider == null || model.isEmpty) {
      _showSnackBar('请先选择模型');
      return;
    }
    final features = provider.featuresForModel(model);
    if (_mode == _ImageWorkbenchMode.generate &&
        features.modelType != ModelType.imageGeneration) {
      _showSnackBar('请选择生图模型');
      return;
    }
    if (_mode == _ImageWorkbenchMode.edit &&
        features.modelType != ModelType.imageEdit) {
      _showSnackBar('请选择图片编辑模型');
      return;
    }
    if (_mode == _ImageWorkbenchMode.edit &&
        (_sourceImagePath ?? '').trim().isEmpty) {
      _showSnackBar('请选择待编辑图片');
      return;
    }

    setState(() {
      _submitting = true;
    });
    try {
      late final Map<String, dynamic> response;
      if (_mode == _ImageWorkbenchMode.generate) {
        response = await ApiService.generateImage(
          provider: provider,
          model: model,
          prompt: prompt,
          requestMode: features.imageRequestMode,
        );
      } else {
        response = await ApiService.editImage(
          provider: provider,
          model: model,
          imagePath: _sourceImagePath!,
          prompt: prompt,
          requestMode: features.imageRequestMode,
        );
      }
      final imageUris =
          (response['imageUris'] as List?)
              ?.map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList() ??
          <String>[];
      if (imageUris.isEmpty) {
        _showSnackBar('接口未返回图片');
        return;
      }
      final record = ImageGenerationRecord.create(
        providerId: provider.id,
        model: model,
        modelType: features.modelType,
        prompt: prompt,
        imageUris: imageUris,
        sourceImagePath:
            _mode == _ImageWorkbenchMode.edit ? _sourceImagePath : null,
        revisedPrompt: response['revisedPrompt']?.toString(),
      );
      final next = <ImageGenerationRecord>[record, ..._history];
      await Storage.saveImageGenerationHistory(next);
      if (!mounted) return;
      setState(() {
        _history = next;
      });
      _showSnackBar('处理完成，共返回 ${imageUris.length} 张图片');
    } catch (error) {
      _showSnackBar('请求失败: $error');
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  /// 构建单条历史记录卡片。
  Widget _buildHistoryCard(BuildContext context, ImageGenerationRecord record) {
    final color = Theme.of(context).colorScheme;
    final firstUri = record.imageUris.isEmpty ? null : record.imageUris.first;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  record.modelType == ModelType.imageEdit
                      ? Icons.auto_fix_high_outlined
                      : Icons.image_outlined,
                  size: 16,
                  color: color.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${record.model} · ${_formatTime(record.createdAt)}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: color.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              record.prompt,
              style: TextStyle(color: color.onSurface, fontSize: 13.5),
            ),
            if (record.revisedPrompt != null &&
                record.revisedPrompt!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '修订提示词：${record.revisedPrompt!.trim()}',
                  style: TextStyle(
                    color: color.onSurfaceVariant,
                    fontSize: 12.5,
                  ),
                ),
              ),
            if (firstUri != null) ...[
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ImagePreviewPage(imageUri: Uri.parse(firstUri)),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _buildImageByUri(firstUri),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 根据 URI 类型构建缩略图组件。
  Widget _buildImageByUri(String rawUri) {
    final uri = Uri.tryParse(rawUri);
    final isHttp = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    final isFile = uri != null && uri.scheme == 'file';
    if (isHttp) {
      return Image.network(
        rawUri,
        height: 180,
        width: double.infinity,
        fit: BoxFit.cover,
      );
    }
    if (isFile) {
      return Image.file(
        File(uri.toFilePath()),
        height: 180,
        width: double.infinity,
        fit: BoxFit.cover,
      );
    }
    return Image.file(
      File(rawUri),
      height: 180,
      width: double.infinity,
      fit: BoxFit.cover,
    );
  }

  void _showSnackBar(String text) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  /// 将时间格式化为 `MM-dd HH:mm`。
  String _formatTime(DateTime time) {
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }
}
