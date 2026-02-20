/// 单次工具调用日志，用于在消息气泡中展示执行过程。
class ToolExecutionLog {
  /// OpenAI tool_call 的唯一 ID。
  final String callId;

  /// 工具名称，例如 `web_fetch`、`python_exec`。
  final String toolName;

  /// 调用状态：`success` / `error` / `skipped`。
  final String status;

  /// 简短摘要（用于列表显示）。
  final String summary;

  /// 可选错误信息。
  final String? error;

  /// 执行耗时（毫秒）。
  final int? durationMs;

  const ToolExecutionLog({
    required this.callId,
    required this.toolName,
    required this.status,
    required this.summary,
    this.error,
    this.durationMs,
  });

  /// 是否成功状态。
  bool get isSuccess => status == 'success';

  /// 是否失败状态。
  bool get isError => status == 'error';

  /// 序列化日志对象。
  Map<String, dynamic> toJson() => {
    'callId': callId,
    'toolName': toolName,
    'status': status,
    'summary': summary,
    if (error != null) 'error': error,
    if (durationMs != null) 'durationMs': durationMs,
  };

  /// 从 JSON 恢复日志对象。
  factory ToolExecutionLog.fromJson(Map<String, dynamic> json) {
    final durationRaw = json['durationMs'];
    return ToolExecutionLog(
      callId: (json['callId'] ?? '').toString(),
      toolName: (json['toolName'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      summary: (json['summary'] ?? '').toString(),
      error: json['error']?.toString(),
      durationMs: durationRaw is num ? durationRaw.toInt() : null,
    );
  }
}
