/// Python 代码执行结果。
class PythonExecutionResult {
  final String stdout;
  final String stderr;
  final int exitCode;
  final Duration duration;
  final bool timedOut;

  const PythonExecutionResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.duration,
    required this.timedOut,
  });

  bool get isSuccess => exitCode == 0 && !timedOut;
}
