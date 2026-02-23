/**
 * bridge_api.js
 *
 * Flutter -> JS 的公开 API。
 * 约束：仅在此处暴露 window.ChatBridge，避免散落定义导致难以维护。
 */

// ===== Flutter → JS API (window.ChatBridge) =====
window.ChatBridge = {
  /** 添加一条消息 */
  addMessage(jsonStr) {
    const msg = JSON.parse(jsonStr);
    state.messages.push(msg);
    // 移除空状态提示
    const emptyEl = $list.querySelector('.empty-state');
    if (emptyEl) {
      emptyEl.remove();
      // 从空状态过渡到有消息：如果有 system prompt，在顶部插入卡片
      if (state.systemPrompt) {
        $list.insertAdjacentHTML('afterbegin', renderSystemPromptCard());
      }
    }
    const wasAtBottom = isNearBottom();
    $list.insertAdjacentHTML('beforeend', renderMessage(msg));
    mountAssistantShadowContent(msg.id, $list);
    if (wasAtBottom) scrollToBottom(false);
  },

  /** 更新消息内容（流式追加） */
  updateMessageContent(id, content) {
    const msg = state.messages.find((m) => m.id === id);
    if (!msg) return;
    msg.content = content;
    updateMessageDOM(msg);
    if (isNearBottom()) scrollToBottom(false);
  },

  /** 更新思考内容（流式追加） */
  updateThinkingContent(id, content, timeMs) {
    const msg = state.messages.find((m) => m.id === id);
    if (!msg) return;
    msg.reasoning = content;
    if (timeMs !== undefined) msg.reasoningTimeMs = timeMs;
    updateMessageDOM(msg);
    if (isNearBottom()) scrollToBottom(false);
  },

  /** 标记消息流式结束 */
  endStreaming(id, canContinue) {
    const msg = state.messages.find((m) => m.id === id);
    if (!msg) return;
    msg.isStreaming = false;
    msg.canContinue = !!canContinue;
    updateMessageDOM(msg);
  },

  /** 删除消息 */
  deleteMessage(id) {
    const idx = state.messages.findIndex((m) => m.id === id);
    if (idx === -1) return;
    state.messages.splice(idx, 1);
    const el = $list.querySelector(`.msg[data-id="${id}"]`);
    if (el) el.remove();
    // 更新 isLast 标记
    if (state.messages.length > 0) {
      const last = state.messages[state.messages.length - 1];
      last.isLast = true;
      updateMessageDOM(last);
    }
  },

  /** 清空所有消息（切换会话） */
  clearMessages() {
    state.messages = [];
    renderAllMessages();
  },

  /** 批量加载消息（初始加载或历史分页） */
  loadMessages(jsonStr, prepend) {
    const msgs = JSON.parse(jsonStr);
    if (prepend) {
      // 历史消息：记录当前滚动位置
      const oldHeight = $list.scrollHeight;
      state.messages = msgs.concat(state.messages);
      renderAllMessages();
      // 保持滚动位置
      const newHeight = $list.scrollHeight;
      $list.scrollTop = newHeight - oldHeight;
    } else {
      state.messages = msgs;
      renderAllMessages();
      scrollToBottom(false);
    }
  },

  /** 设置生成状态 */
  setGeneratingState(isGenerating) {
    state.isGenerating = isGenerating;
    updateSendButton();
    refreshMessageActionButtonsState();
    if (isGenerating) {
      $input.placeholder = '消息生成中...';
    } else {
      $input.placeholder = '输入消息...';
    }
  },

  /** 设置系统提示词 */
  setSystemPrompt(text) {
    state.systemPrompt = text || '';
    renderAllMessages();
  },

  /** 添加工具日志 */
  addToolLog(messageId, logJson) {
    const msg = state.messages.find((m) => m.id === messageId);
    if (!msg) return;
    const log = JSON.parse(logJson);
    if (!msg.toolLogs) msg.toolLogs = [];
    msg.toolLogs.push(log);
    updateMessageDOM(msg);
    if (isNearBottom()) scrollToBottom(false);
  },

  /** 设置附件预览 */
  setAttachments(jsonStr) {
    state.attachments = JSON.parse(jsonStr);
    renderAttachments();
    updateSendButton();
  },

  /** 设置主题色 */
  setTheme(jsonStr) {
    const colors = JSON.parse(jsonStr);
    const root = document.documentElement;
    for (const [key, value] of Object.entries(colors)) {
      root.style.setProperty(`--${key}`, value);
    }
  },

  /** 设置模型信息 */
  setModelInfo(name, supportsVision, supportsTools) {
    const normalizedName = (name || '').trim();
    const hasModel = normalizedName.length > 0;
    state.model = normalizedName;
    state.modelSupportsVision = !!supportsVision;
    state.modelSupportsTools = !!supportsTools;
    $modelName.textContent = hasModel ? normalizedName : '选择模型';
    if ($modelCaps) {
      $modelCaps.innerHTML = renderModelCapabilityBadges(
        state.modelSupportsVision,
        state.modelSupportsTools,
        hasModel,
      );
    }
    updateSendButton();
  },

  /** 设置流式开关状态 */
  setStreamingState(isStreaming, supported) {
    state.isStreaming = isStreaming;
    state.streamingSupported = supported;
    $streamCheck.checked = isStreaming;
    $streamCheck.disabled = !supported;
  },

  /** 设置加载更多状态 */
  setLoadingMore(loading) {
    state.isLoadingMore = loading;
  },

  /** 设置本地图片代理服务器 base URL */
  setImageProxyBase(base) {
    state.imageProxyBase = base || '';
  },

  /** 滚动到底部 */
  scrollToBottom(animated) {
    scrollToBottom(animated);
  },
};
