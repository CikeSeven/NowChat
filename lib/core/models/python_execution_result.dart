/// Python 代码执行结果。
class PythonExecutionResult {
  /// 标准输出内容。
  final String stdout;

  /// 错误输出内容。
  final String stderr;

  /// 进程退出码（0 通常表示成功）。
  final int exitCode;

  /// 执行耗时。
  final Duration duration;

  /// 是否因超时被中断。
  final bool timedOut;

  const PythonExecutionResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.duration,
    required this.timedOut,
  });

  /// 是否执行成功（未超时且退出码为 0）。
  bool get isSuccess => exitCode == 0 && !timedOut;
}
