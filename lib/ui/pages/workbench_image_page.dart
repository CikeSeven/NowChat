import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:now_chat/app/router.dart';
import 'package:now_chat/core/models/ai_provider_config.dart';
import 'package:now_chat/core/models/image_generation_task.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:now_chat/providers/image_generation_queue_provider.dart';
import 'package:now_chat/providers/settings_provider.dart';
import 'package:now_chat/ui/pages/image_preview_page.dart';
import 'package:now_chat/util/app_logger.dart';
import 'package:provider/provider.dart';

enum _ImageWorkbenchMode { generate, edit }

/// 工作台生图页：
/// - 上部显示任务队列（排队中 / 生成中 / 已完成 / 失败）
/// - 下部固定输入区（模式、选图、提示词、加入队列）
class WorkbenchImagePage extends StatefulWidget {
  const WorkbenchImagePage({
    super.key,
    this.listColumns = 1,
  });

  /// 图片记录列表列数：支持 1 列或 2 列。
  final int listColumns;

  @override
  State<WorkbenchImagePage> createState() => WorkbenchImagePageState();
}

class WorkbenchImagePageState extends State<WorkbenchImagePage> {
  final TextEditingController _promptController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  _ImageWorkbenchMode _mode = _ImageWorkbenchMode.generate;
  String? _sourceImagePath;
  bool _composerCollapsed = false;
  final Set<String> _selectedTaskIds = <String>{};
  final Set<String> _expandedPromptTaskIds = <String>{};

  bool get _isSelectionMode => _selectedTaskIds.isNotEmpty;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final queueProvider = context.watch<ImageGenerationQueueProvider>();
    final settings = context.watch<SettingsProvider>();
    final chatProvider = context.watch<ChatProvider>();
    final tasks = _sortedTasks(queueProvider.tasks);
    final color = Theme.of(context).colorScheme;

    return WillPopScope(
      onWillPop: () async => !consumeBackAction(),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              children: [
                Row(
                  children: [
                    Text(
                      '生成记录',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: color.onSurface,
                      ),
                    ),
                    const Spacer(),
                    _buildStatChip(
                      context,
                      label: '生成中 ${queueProvider.runningCount}',
                    ),
                    const SizedBox(width: 6),
                    _buildStatChip(
                      context,
                      label: '排队 ${queueProvider.queuedCount}',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_isSelectionMode) ...[
                  Row(
                    children: [
                      Text(
                        '已选 ${_selectedTaskIds.length}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: color.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _clearSelection,
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 6),
                      FilledButton.tonalIcon(
                        onPressed: () => _deleteSelectedTasks(queueProvider, tasks),
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('删除'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                if (tasks.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        '暂无任务，点击下方“加入生图队列”开始创建',
                        style: TextStyle(color: color.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  _buildTaskList(
                    context: context,
                    tasks: tasks,
                    queueProvider: queueProvider,
                  ),
              ],
            ),
          ),
          _buildComposer(
            context: context,
            settings: settings,
            chatProvider: chatProvider,
            queueProvider: queueProvider,
          ),
        ],
      ),
    );
  }

  /// 消费生图页内部返回事件。
  /// 返回 true 表示已消费（不应继续触发外层返回逻辑）。
  bool consumeBackAction() {
    // 1) 批量选择态：优先取消多选。
    if (_isSelectionMode) {
      _clearSelection();
      return true;
    }
    // 2) 编辑模式已选图片：优先清空已选原图。
    if ((_sourceImagePath ?? '').trim().isNotEmpty) {
      setState(() {
        _sourceImagePath = null;
      });
      return true;
    }
    return false;
  }

  /// 列表顶部状态统计标签。
  Widget _buildStatChip(BuildContext context, {required String label}) {
    final color = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color.onSurfaceVariant,
          fontSize: 11.8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 底部输入区：模式、选图、提示词、配置入口、入队按钮。
  Widget _buildComposer({
    required BuildContext context,
    required SettingsProvider settings,
    required ChatProvider chatProvider,
    required ImageGenerationQueueProvider queueProvider,
  }) {
    final color = Theme.of(context).colorScheme;
    final modelSummary = _buildCurrentModelSummary(
      settings: settings,
      chatProvider: chatProvider,
    );
    // 尺寸配置统一：生图与编辑共用同一默认尺寸。
    final sizeSummary = settings.defaultImageGenerateSize;
    final countSummary = settings.defaultImageGenerateCount;
    if (_composerCollapsed) {
      return SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          decoration: BoxDecoration(
            color: color.surface,
            border: Border(top: BorderSide(color: color.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '输入区已收起',
                  style: TextStyle(
                    fontSize: 12,
                    color: color.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _composerCollapsed = false;
                  });
                },
                icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
                label: const Text('展开'),
              ),
            ],
          ),
        ),
      );
    }
    return SafeArea(
      top: false,
      child: Container(
        // 底部输入区做紧凑化，减少对内容列表的遮挡。
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        decoration: BoxDecoration(
          color: color.surface,
          border: Border(top: BorderSide(color: color.outlineVariant)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _mode == _ImageWorkbenchMode.generate
                        ? '模型：$modelSummary  ·  尺寸：$sizeSummary  ·  数量：$countSummary'
                        : '模型：$modelSummary  ·  尺寸：$sizeSummary',
                    style: TextStyle(
                      fontSize: 11.8,
                      color: color.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _composerCollapsed = true;
                    });
                  },
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                  label: const Text('收起'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                  ),
                ),
              ],
            ),
            if (_mode == _ImageWorkbenchMode.edit) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickSourceImage,
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
                      height: 72,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 6),
            TextField(
              controller: _promptController,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                labelText: _mode == _ImageWorkbenchMode.generate ? '生图提示词' : '编辑提示词',
                hintText:
                    _mode == _ImageWorkbenchMode.generate
                        ? '例如：科幻城市夜景，霓虹灯，电影感'
                        : '例如：保持主体不变，把背景改为海边落日',
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(context, AppRoutes.imageGenerationSettings);
                  },
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('配置'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Builder(
                  builder: (modeContext) {
                    Offset tapPosition = Offset.zero;
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTapDown: (details) => tapPosition = details.globalPosition,
                      onTap: () => _showModeMenu(modeContext, tapPosition),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: color.outlineVariant),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _mode == _ImageWorkbenchMode.generate
                                  ? Icons.image_outlined
                                  : Icons.auto_fix_high_outlined,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _mode == _ImageWorkbenchMode.generate
                                  ? '图片生成'
                                  : '图片编辑',
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.unfold_more, size: 18),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _enqueueTask(
                    context: context,
                    settings: settings,
                    chatProvider: chatProvider,
                    queueProvider: queueProvider,
                  ),
                  icon: const Icon(Icons.playlist_add_rounded),
                  label: Text(
                    _mode == _ImageWorkbenchMode.generate
                        ? '加入生图队列'
                        : '加入编辑队列',
                  ),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 将任务按状态优先级和时间排序。
  List<ImageGenerationTask> _sortedTasks(List<ImageGenerationTask> input) {
    final tasks = List<ImageGenerationTask>.from(input);
    final priority = <ImageGenerationTaskStatus, int>{
      ImageGenerationTaskStatus.running: 0,
      ImageGenerationTaskStatus.queued: 1,
      ImageGenerationTaskStatus.failed: 2,
      ImageGenerationTaskStatus.succeeded: 3,
      ImageGenerationTaskStatus.canceled: 4,
    };
    tasks.sort((a, b) {
      final p = (priority[a.status] ?? 99) - (priority[b.status] ?? 99);
      if (p != 0) return p;
      return b.createdAt.compareTo(a.createdAt);
    });
    return tasks;
  }

  /// 构建当前使用模型描述（仅展示，不在此页编辑）。
  String _buildCurrentModelSummary({
    required SettingsProvider settings,
    required ChatProvider chatProvider,
  }) {
    final providerId =
        _mode == _ImageWorkbenchMode.generate
            ? settings.defaultImageGenerationProviderId
            : settings.defaultImageEditProviderId;
    final model =
        _mode == _ImageWorkbenchMode.generate
            ? settings.defaultImageGenerationModel
            : settings.defaultImageEditModel;
    if ((providerId ?? '').trim().isEmpty || (model ?? '').trim().isEmpty) {
      return '未配置';
    }
    final provider = chatProvider.getProviderById(providerId!);
    if (provider == null) return '未配置';
    return '${provider.name} · ${provider.displayNameForModel(model!.trim())}';
  }

  /// 加入队列（而非立即执行）。
  Future<void> _enqueueTask({
    required BuildContext context,
    required SettingsProvider settings,
    required ChatProvider chatProvider,
    required ImageGenerationQueueProvider queueProvider,
  }) async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      _showSnackBar('请输入提示词');
      return;
    }
    final providerId =
        _mode == _ImageWorkbenchMode.generate
            ? settings.defaultImageGenerationProviderId
            : settings.defaultImageEditProviderId;
    final model =
        _mode == _ImageWorkbenchMode.generate
            ? settings.defaultImageGenerationModel
            : settings.defaultImageEditModel;
    if ((providerId ?? '').trim().isEmpty || (model ?? '').trim().isEmpty) {
      _showSnackBar('请先到“生图设置”配置默认模型');
      return;
    }
    if (_mode == _ImageWorkbenchMode.edit &&
        (_sourceImagePath ?? '').trim().isEmpty) {
      _showSnackBar('请先选择待编辑图片');
      return;
    }
    final provider = chatProvider.getProviderById(providerId!);
    if (provider == null) {
      _showSnackBar('默认模型对应 Provider 不存在，请重新配置');
      return;
    }
    final features = provider.featuresForModel(model!.trim());
    if (_mode == _ImageWorkbenchMode.generate &&
        features.modelType != ModelType.imageGeneration) {
      _showSnackBar('当前默认模型不是生图模型，请在设置页调整');
      return;
    }
    if (_mode == _ImageWorkbenchMode.edit &&
        features.modelType != ModelType.imageEdit) {
      _showSnackBar('当前默认模型不是图片编辑模型，请在设置页调整');
      return;
    }
    // 尺寸配置唯一来源：生图设置页当前值（SettingsProvider 内存态）。
    final selectedSize = settings.defaultImageGenerateSize;
    final selectedCount =
        _mode == _ImageWorkbenchMode.generate
            ? settings.defaultImageGenerateCount
            : 1;
    AppLogger.i(
      'WorkbenchImage.enqueue settings: mode=${_mode.name}, '
      'providerSize=${settings.defaultImageGenerateSize}, '
      'finalSize=$selectedSize, '
      'providerCount=${settings.defaultImageGenerateCount}, finalCount=$selectedCount',
    );
    final task = ImageGenerationTask.createQueued(
      mode:
          _mode == _ImageWorkbenchMode.generate
              ? ImageGenerationTaskMode.generate
              : ImageGenerationTaskMode.edit,
      providerId: provider.id,
      model: model,
      requestMode: features.imageRequestMode,
      prompt: prompt,
      sourceImagePath: _sourceImagePath,
      size: selectedSize,
      requestCount: selectedCount,
    );
    await queueProvider.enqueueTask(task);
    if (!mounted) return;
    setState(() {
      _promptController.clear();
      if (_mode == _ImageWorkbenchMode.edit) {
        _sourceImagePath = null;
      }
    });
  }

  /// 选择图片编辑原图。
  Future<void> _pickSourceImage() async {
    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    setState(() {
      _sourceImagePath = image.path;
    });
  }

  Widget _buildTaskCard({
    required BuildContext context,
    required ImageGenerationTask task,
    required ImageGenerationQueueProvider queueProvider,
    EdgeInsetsGeometry margin = const EdgeInsets.only(bottom: 8),
  }) {
    final color = Theme.of(context).colorScheme;
    // 记录卡片使用浅主题色混合，保证层次感但不过度抢视觉焦点。
    final cardColor = Color.alphaBlend(
      color.primary.withAlpha(17),
      color.surfaceContainerLow,
    );
    final isSelected = _selectedTaskIds.contains(task.id);
    final deletable = _isTaskDeletable(task);
    final firstUri = task.resultImageUris.isEmpty
        ? null
        : task.resultImageUris.first;
    final prompt = task.prompt.trim();
    final isLongPrompt = prompt.length > 120;
    final isPromptExpanded = _expandedPromptTaskIds.contains(task.id);
    return GestureDetector(
      onLongPress: () => _onTaskLongPress(task),
      onTap: () => _onTaskTap(task, firstUri),
      child: Card(
        color: cardColor,
        margin: margin,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side:
              isSelected
                  ? BorderSide(color: color.primary, width: 1.4)
                  : BorderSide.none,
        ),
        child: Padding(
          // 缩短顶部与整体内边距，让记录卡片更紧凑。
          padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildStatusChip(context, task.status),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${task.model} · ${_formatTime(task.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: color.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (_isSelectionMode)
                    Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color:
                          isSelected ? color.primary : color.onSurfaceVariant,
                      size: 20,
                    )
                  else if (deletable)
                    IconButton(
                      tooltip: '删除',
                      onPressed: () => _deleteSingleTask(queueProvider, task),
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 1),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '提示词',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: color.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '复制提示词',
                    onPressed: () => _copyPrompt(prompt),
                    icon: const Icon(Icons.content_copy_rounded, size: 18),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
              SelectableText(
                prompt,
                maxLines: isLongPrompt && !isPromptExpanded ? 3 : null,
                style: TextStyle(
                  color: color.onSurface,
                  fontSize: 13.5,
                ),
              ),
              if (isLongPrompt)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _togglePromptExpand(task.id),
                      icon: Icon(
                        isPromptExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 16,
                      ),
                      label: Text(isPromptExpanded ? '收起提示词' : '展开提示词'),
                    ),
                  ),
                ),
              if ((task.revisedPrompt ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '修订提示词：${task.revisedPrompt!.trim()}',
                    style: TextStyle(
                      color: color.onSurfaceVariant,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              if ((task.errorMessage ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    task.errorMessage!.trim(),
                    style: TextStyle(
                      color: color.error,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              if (task.resultImageUris.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildTaskImagesGrid(task.resultImageUris),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 根据列数构建记录列表：
  /// - 1 列：标准纵向卡片列表
  /// - 2 列：自适应双列卡片列表
  Widget _buildTaskList({
    required BuildContext context,
    required List<ImageGenerationTask> tasks,
    required ImageGenerationQueueProvider queueProvider,
  }) {
    final columns = widget.listColumns == 2 ? 2 : 1;
    if (columns == 1) {
      return Column(
        children:
            tasks
                .map(
                  (task) => _buildTaskCard(
                    context: context,
                    task: task,
                    queueProvider: queueProvider,
                  ),
                )
                .toList(),
      );
    }
    return LayoutBuilder(
      builder: (layoutContext, constraints) {
        const spacing = 8.0;
        final itemWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children:
              tasks
                  .map(
                    (task) => SizedBox(
                      width: itemWidth,
                      child: _buildTaskCard(
                        context: context,
                        task: task,
                        queueProvider: queueProvider,
                        margin: EdgeInsets.zero,
                      ),
                    ),
                  )
                  .toList(),
        );
      },
    );
  }

  Widget _buildStatusChip(BuildContext context, ImageGenerationTaskStatus status) {
    final color = Theme.of(context).colorScheme;
    final (text, background) = switch (status) {
      ImageGenerationTaskStatus.running => ('生成中', color.primaryContainer),
      ImageGenerationTaskStatus.queued => ('排队中', color.secondaryContainer),
      ImageGenerationTaskStatus.succeeded => ('已完成', color.tertiaryContainer),
      ImageGenerationTaskStatus.failed => ('失败', color.errorContainer),
      ImageGenerationTaskStatus.canceled => ('已取消', color.surfaceContainerHighest),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color.onSurface,
        ),
      ),
    );
  }

  /// 任务是否允许删除（运行中的任务不支持直接删除）。
  bool _isTaskDeletable(ImageGenerationTask task) {
    return task.status != ImageGenerationTaskStatus.running;
  }

  /// 卡片点击行为：多选态切换选中，普通态预览图片。
  void _onTaskTap(ImageGenerationTask task, String? firstUri) {
    if (_isSelectionMode) {
      _toggleSelection(task.id);
      return;
    }
    if (firstUri == null) return;
    final previewUri = Uri.parse(_normalizeDisplayImageUri(firstUri));
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImagePreviewPage(imageUri: previewUri),
      ),
    );
  }

  /// 同一任务的结果图宫格展示。
  Widget _buildTaskImagesGrid(List<String> imageUris) {
    if (imageUris.length == 1) {
      final only = imageUris.first;
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: _buildImageTile(only, height: 108),
      );
    }
    final displayUris = imageUris.take(4).toList(growable: false);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1.15,
      ),
      itemCount: displayUris.length,
      itemBuilder: (context, index) {
        final uri = displayUris[index];
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: _buildImageTile(uri, height: 84),
        );
      },
    );
  }

  /// 单张缩略图渲染并承载点击预览。
  Widget _buildImageTile(String rawUri, {required double height}) {
    final normalizedUri = _normalizeDisplayImageUri(rawUri);
    final previewUri = Uri.parse(normalizedUri);
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ImagePreviewPage(imageUri: previewUri),
          ),
        );
      },
      child: _buildImageByUriWithHeight(
        rawUri: rawUri,
        forcedHeight: height,
      ),
    );
  }

  /// 卡片长按行为：进入多选并切换当前项。
  void _onTaskLongPress(ImageGenerationTask task) {
    if (!_isTaskDeletable(task)) {
      _showSnackBar('运行中的任务暂不支持删除');
      return;
    }
    _toggleSelection(task.id);
  }

  void _toggleSelection(String taskId) {
    setState(() {
      if (_selectedTaskIds.contains(taskId)) {
        _selectedTaskIds.remove(taskId);
      } else {
        _selectedTaskIds.add(taskId);
      }
    });
  }

  void _clearSelection() {
    if (_selectedTaskIds.isEmpty) return;
    setState(() {
      _selectedTaskIds.clear();
    });
  }

  Future<void> _deleteSingleTask(
    ImageGenerationQueueProvider queueProvider,
    ImageGenerationTask task,
  ) async {
    final ok = await _confirmDelete(
      title: '删除任务',
      content: '确认删除该任务记录吗？删除后无法恢复。',
    );
    if (!ok) return;
    await queueProvider.deleteTasks(<String>{task.id});
    _expandedPromptTaskIds.remove(task.id);
    _showSnackBar('已删除 1 条记录');
  }

  Future<void> _deleteSelectedTasks(
    ImageGenerationQueueProvider queueProvider,
    List<ImageGenerationTask> tasks,
  ) async {
    if (_selectedTaskIds.isEmpty) return;
    final deletableIds =
        tasks
            .where((task) => _selectedTaskIds.contains(task.id))
            .where(_isTaskDeletable)
            .map((item) => item.id)
            .toSet();
    if (deletableIds.isEmpty) {
      _showSnackBar('没有可删除项');
      return;
    }
    final ok = await _confirmDelete(
      title: '批量删除',
      content: '确认删除已选中的 ${deletableIds.length} 条记录吗？删除后无法恢复。',
    );
    if (!ok) return;
    await queueProvider.deleteTasks(deletableIds);
    if (!mounted) return;
    setState(() {
      _selectedTaskIds.removeAll(deletableIds);
      _expandedPromptTaskIds.removeAll(deletableIds);
    });
    _showSnackBar('已删除 ${deletableIds.length} 条记录');
  }

  Future<bool> _confirmDelete({
    required String title,
    required String content,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  /// 根据 URI 类型构建缩略图。
  Widget _buildImageByUri(String rawUri) {
    return _buildImageByUriWithHeight(rawUri: rawUri, forcedHeight: 108);
  }

  /// 根据 URI 类型构建缩略图（可指定高度，供单图/宫格共用）。
  Widget _buildImageByUriWithHeight({
    required String rawUri,
    required double forcedHeight,
  }) {
    final normalizedRawUri = _normalizeDisplayImageUri(rawUri);
    final uri = Uri.tryParse(normalizedRawUri);
    final isHttp = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    final isFile = uri != null && uri.scheme == 'file';
    if (isHttp) {
      return CachedNetworkImage(
        imageUrl: normalizedRawUri,
        fit: BoxFit.cover,
        height: forcedHeight,
        width: double.infinity,
        placeholder:
            (_, __) => Container(
              height: forcedHeight,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        errorWidget:
            (_, __, ___) => Container(
              height: forcedHeight,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image_outlined),
            ),
      );
    }
    if (isFile) {
      return Image.file(
        File(uri.toFilePath()),
        height: forcedHeight,
        width: double.infinity,
        fit: BoxFit.cover,
      );
    }
    return Image.file(
      File(normalizedRawUri),
      height: forcedHeight,
      width: double.infinity,
      fit: BoxFit.cover,
    );
  }

  /// 兼容无协议头的图片地址（例如 `host/path`）。
  String _normalizeDisplayImageUri(String rawUri) {
    final value = rawUri.trim();
    if (value.isEmpty) return value;
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) return value;
    if (value.startsWith('//')) return 'https:$value';
    final looksLikeHostPath = RegExp(
      r'^[A-Za-z0-9.-]+\.[A-Za-z]{2,}(:\d+)?/.+',
    ).hasMatch(value);
    if (looksLikeHostPath) return 'https://$value';
    return value;
  }

  void _showSnackBar(String text) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  /// 切换提示词折叠状态，默认长文本折叠显示，按需展开完整内容。
  void _togglePromptExpand(String taskId) {
    setState(() {
      if (_expandedPromptTaskIds.contains(taskId)) {
        _expandedPromptTaskIds.remove(taskId);
      } else {
        _expandedPromptTaskIds.add(taskId);
      }
    });
  }

  /// 复制提示词，并显示可手动关闭的提示，避免挡住底部操作区域。
  Future<void> _copyPrompt(String prompt) async {
    final value = prompt.trim();
    if (value.isEmpty) {
      _showSnackBar('提示词为空，无法复制');
      return;
    }
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('提示词已复制'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: '关闭',
          onPressed: () => messenger.hideCurrentSnackBar(),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }

  /// 模式切换菜单：交互与设置页主题切换保持一致。
  Future<void> _showModeMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<_ImageWorkbenchMode>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(
          value: _ImageWorkbenchMode.generate,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('图片生成'),
              if (_mode == _ImageWorkbenchMode.generate)
                const Icon(Icons.check, color: Colors.blue),
            ],
          ),
        ),
        PopupMenuItem(
          value: _ImageWorkbenchMode.edit,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('图片编辑'),
              if (_mode == _ImageWorkbenchMode.edit)
                const Icon(Icons.check, color: Colors.blue),
            ],
          ),
        ),
      ],
    );
    if (selected == null || !mounted) return;
    setState(() {
      _mode = selected;
      _sourceImagePath = null;
    });
  }
}
