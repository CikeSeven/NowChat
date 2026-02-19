part of '../chat_provider.dart';

/// ChatProviderGeneration 扩展方法集合。
extension ChatProviderGeneration on ChatProvider {
  /// 判断指定助手消息是否存在“继续生成”入口。
  bool canContinueAssistantMessage(int chatId, int assistantMessageId) {
    final pending = _pendingContinuations[chatId];
    if (pending == null) return false;
    return pending.assistantMessageId == assistantMessageId;
  }

  /// 请求中断当前会话生成。
  void interruptGeneration(int chatId) {
    final controller = _abortControllers[chatId];
    if (controller == null) return;
    controller.abort();
    AppLogger.i('已请求中断会话($chatId)的生成');
  }

  /// 在已有中断上下文上继续生成。
  Future<void> continueGeneratingAssistantMessage(
    int chatId,
    bool isStreaming,
  ) async {
    final chat = getChatById(chatId);
    if (chat == null || chat.isGenerating) return;
    final provider = getProviderById(chat.providerId ?? '');
    if (provider == null) return;
    final pending = _pendingContinuations[chatId];
    if (pending == null) return;

    final messages = await getMessagesByChatId(chatId);
    final assistantIndex = messages.indexWhere(
      (m) => m.isarId == pending.assistantMessageId,
    );
    if (assistantIndex == -1) {
      _pendingContinuations.remove(chatId);
      _notifyStateChanged();
      return;
    }
    final assistantMessage = messages[assistantIndex];
    final anchorIndex = messages.lastIndexWhere(
      (m) => m.isarId == pending.anchorUserMessageId,
    );
    if (anchorIndex == -1 || anchorIndex >= assistantIndex) {
      _pendingContinuations.remove(chatId);
      _notifyStateChanged();
      return;
    }

    final requestMessages = <Message>[
      ...messages.take(assistantIndex + 1),
      Message(
        chatId: chatId,
        role: 'user',
        content: '继续上一条回复未完成的内容，从中断位置接着写，不要重复已输出内容。',
        timestamp: DateTime.now(),
      ),
    ];

    final abortController = GenerationAbortController();
    _abortControllers[chatId] = abortController;
    await _setChatGenerating(chat, true);
    var responseStarted = false;
    var interrupted = false;
    var usedStreaming = false;
    void handleToolLog(Map<String, dynamic> rawLog) {
      _appendToolLogForMessage(
        assistantMessage.isarId,
        ToolExecutionLog.fromJson(rawLog),
      );
    }

    try {
      final effectiveStreaming =
          isStreaming && provider.requestMode.supportsStreaming;
      if (isStreaming && !provider.requestMode.supportsStreaming) {
        AppLogger.w('当前请求方式不支持流式输出，已自动回退为普通请求');
      }

      if (effectiveStreaming) {
        usedStreaming = true;
        beginStreamingMessage(assistantMessage);
        await ApiService.sendChatRequestStreaming(
          provider: provider,
          session: chat,
          isar: isar,
          abortController: abortController,
          overrideMessages: requestMessages,
          onStream: (deltaContent, deltaReasoning) async {
            if (deltaReasoning != null && deltaReasoning.isNotEmpty) {
              assistantMessage.reasoning =
                  (assistantMessage.reasoning ?? '') + deltaReasoning;
            }
            if (deltaContent.isNotEmpty) {
              responseStarted = true;
              assistantMessage.content += deltaContent;
            }
            updateStreamingMessage(assistantMessage);
          },
          onToolLog: handleToolLog,
          onDone: () async {
            await endStreamingMessage(assistantMessage);
          },
        );
      } else {
        final response = await ApiService.sendChatRequest(
          provider: provider,
          session: chat,
          isar: isar,
          abortController: abortController,
          overrideMessages: requestMessages,
          onToolLog: handleToolLog,
        );
        final content = (response['content'] ?? '').toString();
        final reasoning = response['reasoning']?.toString();
        assistantMessage
          ..content += content
          ..reasoning =
              ((assistantMessage.reasoning ?? '') + (reasoning ?? '')).trim()
          ..reasoningTimeMs = response['reasoningTimeMs'];
        if (content.trim().isNotEmpty) {
          responseStarted = true;
        }
        await saveMessage(assistantMessage);
        final rawLogs = response['toolLogs'];
        if (rawLogs is List && rawLogs.isNotEmpty) {
          _setToolLogsForMessage(
            assistantMessage.isarId,
            rawLogs
                .whereType<Map>()
                .map(
                  (item) => ToolExecutionLog.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(),
          );
        }
      }
    } on GenerationAbortedException {
      interrupted = true;
      AppLogger.i('继续生成已中断(chatId=$chatId)');
    } catch (e) {
      if (_hasMessageOutput(assistantMessage)) {
        interrupted = true;
        AppLogger.w('继续生成流式异常，保留已生成内容并允许继续(chatId=$chatId): $e');
      } else {
        AppLogger.w('继续生成失败(chatId=$chatId): $e');
      }
    } finally {
      if (usedStreaming && _isMessageStreaming(assistantMessage.isarId)) {
        await endStreamingMessage(assistantMessage);
      }
      _abortControllers.remove(chatId);
      await _setChatGenerating(chat, false);
    }

    final hasAnyOutput = _hasMessageOutput(assistantMessage);
    if (interrupted && hasAnyOutput) {
      // 用户手动中断时，无论本次是否已开始新增输出，都保留“继续”入口。
      _pendingContinuations[chatId] = pending;
    } else if (responseStarted) {
      _pendingContinuations.remove(chatId);
    }
    _notifyStateChanged();
  }

  /// 删除末尾助手回复并重新生成。
  Future<void> regenerateMessage(int chatId, bool isStreaming) async {
    final chat = getChatById(chatId);
    if (chat == null || chat.isGenerating) return;
    final provider = getProviderById(chat.providerId ?? '');
    if (provider == null) return;

    final messages = await getMessagesByChatId(chatId);
    if (messages.isEmpty) return;

    final lastUserIndex = messages.lastIndexWhere((m) => m.role == 'user');
    if (lastUserIndex == -1) return;

    final trailingAssistantMessages =
        messages
            .skip(lastUserIndex + 1)
            .where((m) => m.role == 'assistant')
            .toList();

    final backupAssistantMessages = List<Message>.from(
      trailingAssistantMessages,
    );
    await _deleteMessagesByIds(
      trailingAssistantMessages.map((m) => m.isarId).toSet(),
    );

    final abortController = GenerationAbortController();
    _abortControllers[chatId] = abortController;
    await _setChatGenerating(chat, true);
    var interrupted = false;
    var usedStreaming = false;
    late final Message aiMsg;
    try {
      aiMsg = Message(
        chatId: chatId,
        role: 'assistant',
        content: '',
        reasoning: '',
        timestamp: DateTime.now(),
      );
      await saveMessage(aiMsg);
      void handleToolLog(Map<String, dynamic> rawLog) {
        _appendToolLogForMessage(
          aiMsg.isarId,
          ToolExecutionLog.fromJson(rawLog),
        );
      }

      final effectiveStreaming =
          isStreaming && provider.requestMode.supportsStreaming;
      if (isStreaming && !provider.requestMode.supportsStreaming) {
        AppLogger.w('当前请求方式不支持流式输出，已自动回退为普通请求');
      }

      String? failureReason;
      var responseStarted = false;

      if (effectiveStreaming) {
        usedStreaming = true;
        beginStreamingMessage(aiMsg);
        Timer? reasoningTimer;
        DateTime? reasoningStartTime;
        try {
          await ApiService.sendChatRequestStreaming(
            provider: provider,
            session: chat,
            isar: isar,
            abortController: abortController,
            onStream: (deltaContent, deltaReasoning) async {
              if (deltaReasoning != null && deltaReasoning.isNotEmpty) {
                if (reasoningStartTime == null) {
                  reasoningStartTime = DateTime.now();
                  reasoningTimer = Timer.periodic(
                    const Duration(milliseconds: 100),
                    (_) async {
                      aiMsg.reasoningTimeMs =
                          DateTime.now()
                              .difference(reasoningStartTime!)
                              .inMilliseconds;
                      updateStreamingMessage(aiMsg);
                    },
                  );
                }
                aiMsg.reasoning = (aiMsg.reasoning ?? '') + deltaReasoning;
              }

              if (deltaContent.isNotEmpty) {
                responseStarted = true;
                reasoningTimer?.cancel();
                aiMsg.content += deltaContent;
              }

              updateStreamingMessage(aiMsg);
            },
            onToolLog: handleToolLog,
            onDone: () async {
              reasoningTimer?.cancel();
              if (reasoningStartTime != null) {
                aiMsg.reasoningTimeMs =
                    DateTime.now()
                        .difference(reasoningStartTime!)
                        .inMilliseconds;
              }
              await endStreamingMessage(aiMsg);
            },
          );
        } on GenerationAbortedException {
          reasoningTimer?.cancel();
          if (reasoningStartTime != null) {
            aiMsg.reasoningTimeMs =
                DateTime.now().difference(reasoningStartTime!).inMilliseconds;
          }
          interrupted = true;
        } catch (e) {
          reasoningTimer?.cancel();
          if (_hasMessageOutput(aiMsg)) {
            interrupted = true;
            AppLogger.w('重新生成流式异常，保留已生成内容并允许继续：$e');
          } else {
            failureReason = e.toString();
          }
        } finally {
          reasoningTimer?.cancel();
        }
      } else {
        try {
          final response = await ApiService.sendChatRequest(
            provider: provider,
            session: chat,
            isar: isar,
            abortController: abortController,
            onToolLog: handleToolLog,
          );
          aiMsg
            ..content = response['content'] ?? ''
            ..reasoning = response['reasoning']
            ..reasoningTimeMs = response['reasoningTimeMs'];
          if (aiMsg.content.trim().isNotEmpty) {
            responseStarted = true;
          }
          await saveMessage(aiMsg);
          final rawLogs = response['toolLogs'];
          if (rawLogs is List && rawLogs.isNotEmpty) {
            _setToolLogsForMessage(
              aiMsg.isarId,
              rawLogs
                  .whereType<Map>()
                  .map(
                    (item) => ToolExecutionLog.fromJson(
                      Map<String, dynamic>.from(item),
                    ),
                  )
                  .toList(),
            );
          }
        } on GenerationAbortedException {
          interrupted = true;
        } catch (e) {
          failureReason = e.toString();
        }
      }

      final hasAnyOutput = _hasMessageOutput(aiMsg);
      final shouldRestoreOldReply = !responseStarted && !interrupted;
      final shouldKeepInterruptedPartial = interrupted && hasAnyOutput;
      if (shouldRestoreOldReply) {
        await _deleteMessagesByIds({aiMsg.isarId});
        if (backupAssistantMessages.isNotEmpty) {
          await _restoreMessages(backupAssistantMessages);
        }
        if (failureReason != null) {
          AppLogger.w('重新发送失败，已恢复旧回复: $failureReason');
        } else {
          AppLogger.w('重新发送未产出有效内容，已恢复旧回复');
        }
      } else if (shouldKeepInterruptedPartial) {
        _pendingContinuations[chatId] = _PendingContinuation(
          assistantMessageId: aiMsg.isarId,
          anchorUserMessageId: messages[lastUserIndex].isarId,
        );
      } else if (interrupted && !hasAnyOutput) {
        await _deleteMessagesByIds({aiMsg.isarId});
        if (backupAssistantMessages.isNotEmpty) {
          await _restoreMessages(backupAssistantMessages);
        }
        _pendingContinuations.remove(chatId);
      } else {
        _pendingContinuations.remove(chatId);
      }
    } finally {
      if (usedStreaming && _isMessageStreaming(aiMsg.isarId)) {
        await endStreamingMessage(aiMsg);
      }
      _abortControllers.remove(chatId);
      await _setChatGenerating(chat, false);
    }
  }

  /// 发送用户消息并生成助手回复。
  Future<void> sendMessage(
    int chatId,
    String userContent,
    bool isStreaming,
    List<String>? attachmentPaths,
  ) async {
    AppLogger.i('发送消息');
    final chat = getChatById(chatId);
    if (chat == null) return;
    final provider = getProviderById(chat.providerId ?? '');
    if (provider == null) {
      await saveMessage(
        Message(
          chatId: chatId,
          role: 'assistant',
          content: '无效的 Provider',
          timestamp: DateTime.now(),
        ),
      );
      _notifyStateChanged();
      return;
    }
    _pendingContinuations.remove(chatId);
    final abortController = GenerationAbortController();
    _abortControllers[chatId] = abortController;
    await _setChatGenerating(chat, true);
    var interrupted = false;
    var usedStreaming = false;
    var responseStarted = false;
    Object? terminalError;
    Message? aiMsg;
    try {
      final userMsg = Message(
        chatId: chatId,
        role: 'user',
        content: userContent,
        imagePaths: attachmentPaths,
        timestamp: DateTime.now(),
      );

      final beforeHookResults = await PluginHookBus.emit(
        'chat_before_send',
        payload: <String, dynamic>{
          'chatId': chatId,
          'providerId': chat.providerId,
          'model': chat.model,
          'isStreaming': isStreaming,
          'message': _toHookMessagePayload(userMsg),
        },
      );
      // 允许 Hook 在发送前改写用户消息（例如统一前后缀、脱敏、模板注入）。
      await _applyHookMessageOverride(
        message: userMsg,
        hookResults: beforeHookResults,
        expectedRole: 'user',
        persist: false,
      );

      await saveMessage(userMsg);

      aiMsg = Message(
        chatId: chatId,
        role: 'assistant',
        content: '',
        reasoning: '',
        timestamp: DateTime.now(),
      );
      final currentAiMsg = aiMsg;

      await saveMessage(currentAiMsg);
      void handleToolLog(Map<String, dynamic> rawLog) {
        _appendToolLogForMessage(
          currentAiMsg.isarId,
          ToolExecutionLog.fromJson(rawLog),
        );
      }

      final effectiveStreaming =
          isStreaming && provider.requestMode.supportsStreaming;
      if (isStreaming && !provider.requestMode.supportsStreaming) {
        AppLogger.w('当前请求方式不支持流式输出，已自动回退为普通请求');
      }

      if (effectiveStreaming) {
        usedStreaming = true;
        beginStreamingMessage(currentAiMsg);
        Timer? reasoningTimer;
        DateTime? reasoningStartTime;

        try {
          await ApiService.sendChatRequestStreaming(
            provider: provider,
            session: chat,
            isar: isar,
            abortController: abortController,
            onStream: (deltaContent, deltaReasoning) async {
              if (deltaReasoning != null && deltaReasoning.isNotEmpty) {
                if (reasoningStartTime == null) {
                  reasoningStartTime = DateTime.now();
                  reasoningTimer = Timer.periodic(
                    const Duration(milliseconds: 100),
                    (_) async {
                      currentAiMsg.reasoningTimeMs =
                          DateTime.now()
                              .difference(reasoningStartTime!)
                              .inMilliseconds;
                      updateStreamingMessage(currentAiMsg);
                    },
                  );
                }
                currentAiMsg.reasoning =
                    (currentAiMsg.reasoning ?? '') + deltaReasoning;
              }

              if (deltaContent.isNotEmpty) {
                responseStarted = true;
                reasoningTimer?.cancel();
                currentAiMsg.content += deltaContent;
              }

              updateStreamingMessage(currentAiMsg);
            },
            onToolLog: handleToolLog,
            onDone: () async {
              AppLogger.i('onDone: 流式请求结束');
              reasoningTimer?.cancel();
              if (reasoningStartTime != null) {
                currentAiMsg.reasoningTimeMs =
                    DateTime.now()
                        .difference(reasoningStartTime!)
                        .inMilliseconds;
              }
              await endStreamingMessage(currentAiMsg);
            },
          );
        } on GenerationAbortedException {
          reasoningTimer?.cancel();
          if (reasoningStartTime != null) {
            currentAiMsg.reasoningTimeMs =
                DateTime.now().difference(reasoningStartTime!).inMilliseconds;
          }
          interrupted = true;
        } catch (e) {
          terminalError = e;
          reasoningTimer?.cancel();
          if (_hasMessageOutput(currentAiMsg)) {
            interrupted = true;
            AppLogger.w('流式异常中断，保留已生成内容并允许继续：$e');
          } else {
            currentAiMsg.content = 'AI 响应出错：${e.toString()}';
            await endStreamingMessage(currentAiMsg);
          }
        } finally {
          reasoningTimer?.cancel();
        }
      } else {
        try {
          final response = await ApiService.sendChatRequest(
            provider: provider,
            session: chat,
            isar: isar,
            abortController: abortController,
            onToolLog: handleToolLog,
          );
          currentAiMsg
            ..content = response['content'] ?? ''
            ..reasoning = response['reasoning']
            ..reasoningTimeMs = response['reasoningTimeMs'];
          if (currentAiMsg.content.trim().isNotEmpty) {
            responseStarted = true;
          }
          await saveMessage(currentAiMsg);
          final rawLogs = response['toolLogs'];
          if (rawLogs is List && rawLogs.isNotEmpty) {
            _setToolLogsForMessage(
              currentAiMsg.isarId,
              rawLogs
                  .whereType<Map>()
                  .map(
                    (item) => ToolExecutionLog.fromJson(
                      Map<String, dynamic>.from(item),
                    ),
                  )
                  .toList(),
            );
          }
        } on GenerationAbortedException {
          interrupted = true;
        } catch (e) {
          terminalError = e;
          currentAiMsg.content = '请求失败: $e';
          await saveMessage(currentAiMsg);
        }
      }

      final hasAnyOutput = _hasMessageOutput(currentAiMsg);
      if (interrupted && hasAnyOutput) {
        _pendingContinuations[chatId] = _PendingContinuation(
          assistantMessageId: currentAiMsg.isarId,
          anchorUserMessageId: userMsg.isarId,
        );
      } else if (interrupted && !hasAnyOutput) {
        await _deleteMessagesByIds({currentAiMsg.isarId});
      } else if (responseStarted) {
        _pendingContinuations.remove(chatId);
      }
    } finally {
      if (usedStreaming && aiMsg != null && _isMessageStreaming(aiMsg.isarId)) {
        await endStreamingMessage(aiMsg);
      }
      _abortControllers.remove(chatId);
      await _setChatGenerating(chat, false);
      final hookResults = await PluginHookBus.emit(
        'chat_after_send',
        payload: <String, dynamic>{
          'chatId': chatId,
          'providerId': chat.providerId,
          'model': chat.model,
          'interrupted': interrupted,
          'responseStarted': responseStarted,
          'error': terminalError?.toString(),
          'message': aiMsg == null ? null : _toHookMessagePayload(aiMsg),
        },
      );
      await _applyHookMessageOverride(
        message: aiMsg,
        hookResults: hookResults,
        expectedRole: 'assistant',
      );
    }
    _notifyStateChanged();
  }

  /// 将 Message 转为 Hook payload，供插件读取与改写。
  Map<String, dynamic> _toHookMessagePayload(Message message) {
    return <String, dynamic>{
      'id': message.isarId,
      'chatId': message.chatId,
      'role': message.role,
      'content': message.content,
      'reasoning': message.reasoning,
      'reasoningTimeMs': message.reasoningTimeMs,
      'imagePaths': message.imagePaths,
      'timestamp': message.timestamp.toIso8601String(),
    };
  }

  /// 应用 Hook 返回的 `message` 覆写对象。
  ///
  /// 协议约定：
  /// - Hook 返回结构：`{"message": { ...可覆写字段... }}`。
  /// - 多个 Hook 同时返回时采用“最后一个有效结果覆盖前者”。
  Future<void> _applyHookMessageOverride({
    required Message? message,
    required List<PluginHookEmitResult> hookResults,
    required String expectedRole,
    bool persist = true,
  }) async {
    if (message == null) return;
    final patch = _extractMessagePatchFromHooks(hookResults);
    if (patch == null) return;
    final changed = _mergeMessagePatch(
      message: message,
      patch: patch,
      expectedRole: expectedRole,
    );
    if (!changed) return;
    if (persist) {
      await saveMessage(message);
    }
  }

  /// 提取 Hook 结果中的 message 补丁（最后一个有效补丁生效）。
  Map<String, dynamic>? _extractMessagePatchFromHooks(
    List<PluginHookEmitResult> hookResults,
  ) {
    Map<String, dynamic>? patch;
    for (final item in hookResults) {
      if (!item.ok) continue;
      final raw = item.data?['message'];
      if (raw is Map<String, dynamic>) {
        patch = raw;
        continue;
      }
      if (raw is Map) {
        patch = raw.map((key, value) => MapEntry(key.toString(), value));
      }
    }
    return patch;
  }

  /// 按白名单字段将 Hook 补丁写回消息对象。
  bool _mergeMessagePatch({
    required Message message,
    required Map<String, dynamic> patch,
    required String expectedRole,
  }) {
    final incomingRole = patch['role']?.toString().trim();
    if (incomingRole != null &&
        incomingRole.isNotEmpty &&
        incomingRole != expectedRole) {
      AppLogger.w('忽略 Hook 消息覆写：role=$incomingRole, expected=$expectedRole');
      return false;
    }

    var changed = false;

    if (patch.containsKey('content')) {
      final content = (patch['content'] ?? '').toString();
      if (content != message.content) {
        message.content = content;
        changed = true;
      }
    }

    if (patch.containsKey('reasoning')) {
      final raw = patch['reasoning'];
      final reasoning = raw == null ? null : raw.toString();
      if (reasoning != message.reasoning) {
        message.reasoning = reasoning;
        changed = true;
      }
    }

    if (patch.containsKey('reasoningTimeMs')) {
      final raw = patch['reasoningTimeMs'];
      final reasoningTimeMs =
          raw == null
              ? null
              : (raw is num ? raw.toInt() : int.tryParse(raw.toString()));
      if (reasoningTimeMs != message.reasoningTimeMs) {
        message.reasoningTimeMs = reasoningTimeMs;
        changed = true;
      }
    }

    if (patch.containsKey('imagePaths')) {
      final raw = patch['imagePaths'];
      if (raw == null) {
        if (message.imagePaths != null) {
          message.imagePaths = null;
          changed = true;
        }
      } else if (raw is List) {
        final imagePaths =
            raw
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty)
                .toList();
        final normalized = imagePaths.isEmpty ? null : imagePaths;
        if (!_sameStringList(normalized, message.imagePaths)) {
          message.imagePaths = normalized;
          changed = true;
        }
      }
    }

    return changed;
  }

  /// 比较两个字符串列表内容是否一致（含 null 情况）。
  bool _sameStringList(List<String>? a, List<String>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 设置会话生成中状态并写回数据库。
  Future<void> _setChatGenerating(ChatSession chat, bool isGenerating) async {
    chat.isGenerating = isGenerating;
    await isar.writeTxn(() async {
      await isar.chatSessions.put(chat);
    });
    _notifyStateChanged();
  }
}
