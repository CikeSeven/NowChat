import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:now_chat/core/models/ai_provider_config.dart';
import 'package:now_chat/core/models/image_generation_record.dart';
import 'package:now_chat/core/models/image_generation_task.dart';
import 'package:now_chat/core/network/api_service.dart';
import 'package:now_chat/providers/settings_provider.dart';
import 'package:now_chat/util/app_logger.dart';
import 'package:now_chat/util/storage.dart';

/// 生图任务队列 Provider。
///
/// 设计目标：
/// 1. 支持后台并发执行与重启恢复；
/// 2. 保证队列状态可持久化；
/// 3. 提供统一的任务增删改查接口，供工作台 UI 使用。
class ImageGenerationQueueProvider extends ChangeNotifier {
  SettingsProvider? _settings;
  bool _initialized = false;
  bool _initializing = false;
  bool _scheduling = false;
  int _activeWorkers = 0;
  final List<ImageGenerationTask> _tasks = <ImageGenerationTask>[];

  List<ImageGenerationTask> get tasks => List<ImageGenerationTask>.unmodifiable(_tasks);

  int get runningCount =>
      _tasks.where((item) => item.status == ImageGenerationTaskStatus.running).length;

  int get queuedCount =>
      _tasks.where((item) => item.status == ImageGenerationTaskStatus.queued).length;

  int get concurrency {
    final next = _settings?.imageQueueConcurrency ??
        SettingsProvider.defaultImageQueueConcurrencyValue;
    if (next < 1) return 1;
    if (next > 4) return 4;
    return next;
  }

  /// 绑定全局设置并触发初始化。
  void bindSettings(SettingsProvider settings) {
    final previousConcurrency = concurrency;
    _settings = settings;
    if (!_initialized && !_initializing) {
      unawaited(_initialize());
      return;
    }
    if (_initialized && previousConcurrency != concurrency) {
      _schedule();
    }
  }

  /// 初始化队列状态：加载本地任务并恢复调度。
  Future<void> _initialize() async {
    if (_initialized || _initializing) return;
    _initializing = true;
    try {
      final loaded = await Storage.loadImageGenerationQueueTasks();
      final normalized =
          loaded.map((task) {
            // 进程重启后，运行中的任务回退为排队，避免卡死在 running。
            if (task.status == ImageGenerationTaskStatus.running) {
              return task.copyWith(
                status: ImageGenerationTaskStatus.queued,
                startedAt: null,
                updatedAt: DateTime.now(),
              );
            }
            return task;
          }).toList(growable: true);
      await _mergeLegacyHistory(normalized);
      _tasks
        ..clear()
        ..addAll(normalized);
      await _persistTasks();
      _initialized = true;
      notifyListeners();
      _schedule();
    } catch (error, stackTrace) {
      AppLogger.e('生图队列初始化失败', error, stackTrace);
    } finally {
      _initializing = false;
    }
  }

  /// 入队任务。
  Future<void> enqueueTask(ImageGenerationTask task) async {
    if (!_initialized && !_initializing) {
      await _initialize();
    }
    _tasks.insert(0, task);
    await _persistTasks();
    notifyListeners();
    _schedule();
  }

  /// 批量删除任务（运行中的任务会被忽略，避免出现状态竞争）。
  Future<void> deleteTasks(Set<String> taskIds) async {
    if (taskIds.isEmpty) return;
    final runningIds =
        _tasks
            .where((item) => item.status == ImageGenerationTaskStatus.running)
            .map((item) => item.id)
            .toSet();
    final allowed = taskIds.difference(runningIds);
    if (allowed.isEmpty) return;
    _tasks.removeWhere((item) => allowed.contains(item.id));
    await _persistTasks();
    notifyListeners();
  }

  /// 重试失败/取消任务。
  Future<void> retryTask(String taskId) async {
    final index = _tasks.indexWhere((item) => item.id == taskId);
    if (index < 0) return;
    final current = _tasks[index];
    if (current.status != ImageGenerationTaskStatus.failed &&
        current.status != ImageGenerationTaskStatus.canceled) {
      return;
    }
    _tasks[index] = current.copyWith(
      status: ImageGenerationTaskStatus.queued,
      errorMessage: null,
      finishedAt: null,
      startedAt: null,
      resultImageUris: const <String>[],
      revisedPrompt: null,
      retryCount: current.retryCount + 1,
      updatedAt: DateTime.now(),
    );
    await _persistTasks();
    notifyListeners();
    _schedule();
  }

  /// 调度器：按并发数拉起排队任务。
  void _schedule() {
    if (!_initialized || _scheduling) return;
    _scheduling = true;
    Future<void>(() async {
      try {
        while (_activeWorkers < concurrency) {
          final queued = _findNextQueuedTask();
          if (queued == null) break;
          final running = queued.copyWith(
            status: ImageGenerationTaskStatus.running,
            startedAt: DateTime.now(),
            updatedAt: DateTime.now(),
            errorMessage: null,
          );
          _replaceTask(running);
          _activeWorkers += 1;
          await _persistTasks();
          notifyListeners();
          unawaited(_runTask(running.id));
        }
      } finally {
        _scheduling = false;
      }
    });
  }

  /// 执行单个任务。
  Future<void> _runTask(String taskId) async {
    try {
      final task = _findTaskById(taskId);
      if (task == null || task.status != ImageGenerationTaskStatus.running) {
        return;
      }
      final providers = await Storage.loadProviders();
      final provider = _findProviderById(providers, task.providerId);
      if (provider == null) {
        throw Exception('Provider 不存在: ${task.providerId}');
      }

      late final Map<String, dynamic> response;
      if (task.mode == ImageGenerationTaskMode.generate) {
        response = await ApiService.generateImage(
          provider: provider,
          model: task.model,
          prompt: task.prompt,
          requestMode: task.requestMode,
          size: task.size,
        );
      } else {
        final source = (task.sourceImagePath ?? '').trim();
        if (source.isEmpty) {
          throw Exception('图片编辑任务缺少 sourceImagePath');
        }
        response = await ApiService.editImage(
          provider: provider,
          model: task.model,
          imagePath: source,
          prompt: task.prompt,
          requestMode: task.requestMode,
          size: task.size,
        );
      }
      final imageUris =
          (response['imageUris'] as List?)
              ?.map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList() ??
          <String>[];
      if (imageUris.isEmpty) {
        throw Exception('接口未返回图片');
      }

      final succeeded = task.copyWith(
        status: ImageGenerationTaskStatus.succeeded,
        resultImageUris: imageUris,
        revisedPrompt: response['revisedPrompt']?.toString(),
        finishedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      _replaceTask(succeeded);
      await _appendRecordFromTask(succeeded);
      await _persistTasks();
      notifyListeners();
    } catch (error, stackTrace) {
      AppLogger.e('执行生图任务失败: task=$taskId', error, stackTrace);
      final current = _findTaskById(taskId);
      if (current != null) {
        _replaceTask(
          current.copyWith(
            status: ImageGenerationTaskStatus.failed,
            errorMessage: error.toString(),
            finishedAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        await _persistTasks();
        notifyListeners();
      }
    } finally {
      _activeWorkers -= 1;
      if (_activeWorkers < 0) _activeWorkers = 0;
      _schedule();
    }
  }

  ImageGenerationTask? _findNextQueuedTask() {
    final queued =
        _tasks
            .where((item) => item.status == ImageGenerationTaskStatus.queued)
            .toList(growable: false);
    if (queued.isEmpty) return null;
    queued.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return queued.first;
  }

  void _replaceTask(ImageGenerationTask task) {
    final index = _tasks.indexWhere((item) => item.id == task.id);
    if (index < 0) return;
    _tasks[index] = task;
  }

  ImageGenerationTask? _findTaskById(String taskId) {
    for (final task in _tasks) {
      if (task.id == taskId) return task;
    }
    return null;
  }

  AIProviderConfig? _findProviderById(
    List<AIProviderConfig> providers,
    String providerId,
  ) {
    for (final provider in providers) {
      if (provider.id == providerId) return provider;
    }
    return null;
  }

  Future<void> _persistTasks() async {
    await Storage.saveImageGenerationQueueTasks(_tasks);
  }

  /// 与历史面板保持兼容：成功任务同步写入历史记录。
  Future<void> _appendRecordFromTask(ImageGenerationTask task) async {
    final history = await Storage.loadImageGenerationHistory();
    final record = ImageGenerationRecord(
      id: task.id,
      createdAt: task.createdAt,
      providerId: task.providerId,
      model: task.model,
      modelType:
          task.mode == ImageGenerationTaskMode.edit
              ? ModelType.imageEdit
              : ModelType.imageGeneration,
      prompt: task.prompt,
      imageUris: task.resultImageUris,
      sourceImagePath: task.sourceImagePath,
      revisedPrompt: task.revisedPrompt,
    );
    final next = <ImageGenerationRecord>[
      record,
      ...history.where((item) => item.id != record.id),
    ];
    await Storage.saveImageGenerationHistory(next);
  }

  /// 兼容旧版数据：将历史记录迁移到任务列表中展示。
  ///
  /// 迁移策略：
  /// - 按 `id` 去重；
  /// - 仅补充缺失项，不覆盖新队列已有状态；
  /// - 首次迁移后会写回新队列存储。
  Future<void> _mergeLegacyHistory(List<ImageGenerationTask> target) async {
    final history = await Storage.loadImageGenerationHistory();
    if (history.isEmpty) return;
    final existingIds = target.map((item) => item.id).toSet();
    for (final record in history) {
      if (existingIds.contains(record.id)) continue;
      target.add(
        ImageGenerationTask(
          id: record.id,
          createdAt: record.createdAt,
          updatedAt: record.createdAt,
          startedAt: record.createdAt,
          finishedAt: record.createdAt,
          mode:
              record.modelType == ModelType.imageEdit
                  ? ImageGenerationTaskMode.edit
                  : ImageGenerationTaskMode.generate,
          status: ImageGenerationTaskStatus.succeeded,
          providerId: record.providerId,
          model: record.model,
          requestMode: ImageRequestMode.inheritProvider,
          size: null,
          prompt: record.prompt,
          sourceImagePath: record.sourceImagePath,
          resultImageUris: record.imageUris,
          revisedPrompt: record.revisedPrompt,
          errorMessage: null,
          retryCount: 0,
        ),
      );
    }
  }
}
