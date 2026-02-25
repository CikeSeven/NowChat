import 'package:now_chat/core/models/image_generation_task.dart';
import 'package:now_chat/util/app_logger.dart';
import 'package:now_chat/util/storage.dart';

/// 生图队列桥接器：
/// - 供核心层（如 AI 工具运行时）提交生图任务；
/// - 优先走运行中的队列 Provider，确保可立即调度；
/// - 若 Provider 不可用，回退为直接写入持久化队列，保证请求不丢。
class ImageGenerationQueueBridge {
  static Future<void> Function(ImageGenerationTask task)? _enqueueHandler;

  /// 注册实时入队处理器（通常由 ImageGenerationQueueProvider 在启动时注册）。
  static void registerEnqueueHandler(
    Future<void> Function(ImageGenerationTask task) handler,
  ) {
    _enqueueHandler = handler;
  }

  /// 注销实时入队处理器。
  static void unregisterEnqueueHandler(
    Future<void> Function(ImageGenerationTask task) handler,
  ) {
    if (_enqueueHandler == handler) {
      _enqueueHandler = null;
    }
  }

  /// 入队任务。
  ///
  /// 说明：
  /// - 当应用内队列 Provider 已就绪时，直接交给 Provider，立即进入调度；
  /// - 当 Provider 尚未就绪时，写入本地队列，后续由 Provider 初始化时接管。
  static Future<void> enqueueTask(ImageGenerationTask task) async {
    final handler = _enqueueHandler;
    if (handler != null) {
      await handler(task);
      return;
    }
    final tasks = await Storage.loadImageGenerationQueueTasks();
    tasks.insert(0, task);
    await Storage.saveImageGenerationQueueTasks(tasks);
    AppLogger.w(
      'ImageQueueBridge fallback enqueue: task=${task.id}, mode=${task.mode.name}',
    );
  }
}

