import 'package:flutter/foundation.dart'; // for kDebugMode
import 'package:logger/logger.dart';

/// 应用日志门面。
///
/// 统一封装第三方 `logger`，便于：
/// 1. 统一日志格式与调用方式；
/// 2. 后续替换日志实现时减少改动面；
/// 3. 在非 debug 环境下默认静默，避免泄漏敏感信息。
class AppLogger {
  /// 全局 logger 实例。
  static final _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 5,
      lineLength: 100,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.dateAndTime,
    ),
  );

  /// Trace 级日志（最细粒度调试信息）。
  static void t(String message) {
    if (kDebugMode) _logger.t(message);
  }

  /// Debug 级日志。
  static void d(String message) {
    if (kDebugMode) _logger.d(message);
  }

  /// Info 级日志（流程节点、状态变化）。
  static void i(String message) {
    if (kDebugMode) _logger.i(message);
  }

  /// Warning 级日志（可恢复异常、降级行为）。
  static void w(String message) {
    if (kDebugMode) _logger.w(message);
  }

  /// Error 级日志（异常与堆栈）。
  ///
  /// 建议在 catch 中同时传入 `error` 与 `stackTrace`，便于定位问题。
  static void e(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) _logger.e(message, error: error, stackTrace: stackTrace);
  }
}
