/**
 * message_renderer.js
 *
 * 负责消息区域 DOM 生成与增量更新：
 * - 全量渲染
 * - 单条消息渲染
 * - 流式场景增量替换
 */

/** 完整重绘消息列表 */
function renderAllMessages() {
  const wasAtBottom = isNearBottom();
  let html = '';

  if (state.isLoadingMore) {
    html += '<div class="loading-more"><div class="spinner"></div></div>';
  }

  // 新会话空状态：显示 system prompt 卡片 + 提示文字
  if (state.messages.length === 0 && !state.isLoadingMore) {
    html += '<div class="empty-state">';
    html += renderSystemPromptCard();
    html += '<span>发送消息以开始新的会话</span>';
    html += '</div>';
  } else {
    // 有消息时，在顶部显示 system prompt 卡片（仅当有内容时）
    if (state.systemPrompt) {
      html += renderSystemPromptCard();
    }
  }

  for (const msg of state.messages) {
    html += renderMessage(msg);
  }

  $list.innerHTML = html;
  mountAllAssistantShadowContents($list);
  if (wasAtBottom) scrollToBottom(false);
}

/** 渲染 System Prompt 卡片 */
function renderSystemPromptCard() {
  const hasContent = state.systemPrompt && state.systemPrompt.trim().length > 0;
  const displayText = hasContent
    ? escHtml(truncate(state.systemPrompt.trim(), 120))
    : '点击设置 System Prompt（可选）';
  const textClass = hasContent ? 'sp-text' : 'sp-text sp-placeholder';
  return `<div class="system-prompt-card ripple" onclick="Bridge.onMessageAction(0,'editSystemPrompt')">
    <div class="sp-header">${icon('tune')}<span>System Prompt</span></div>
    <div class="${textClass}">${displayText}</div>
  </div>`;
}

/** 渲染单条消息 HTML */
function renderMessage(msg) {
  if (msg.role === 'user') return renderUserMessage(msg);
  if (msg.role === 'assistant') return renderAssistantMessage(msg);
  return '';
}

function renderUserMessage(msg) {
  let attachHtml = '';
  if (msg.imagePaths && msg.imagePaths.length > 0) {
    const items = msg.imagePaths
      .map((p) => {
        if (isRenderableImageAttachment(p)) {
          const src = proxyImageUrl(p);
          return `<img src="${escHtml(src)}" onclick="Bridge.onImageTap('${escJs(p)}')" />`;
        }
        return `<span class="file-chip">${escHtml(fileName(p))}</span>`;
      })
      .join('');
    attachHtml = `<div class="msg-attachments">${items}</div>`;
  }
  return `<div class="msg msg-user" data-id="${msg.id}">
    <div class="msg-bubble ripple" ontouchstart="startLongPress(event, ${msg.id})" ontouchend="cancelLongPress()" ontouchcancel="cancelLongPress()" oncontextmenu="handleContextMenu(event, ${msg.id})">${escHtml(msg.content)}${attachHtml}</div>
  </div>`;
}

function renderAssistantMessage(msg) {
  const isStreaming = msg.isStreaming;
  const hasContent = (msg.content || '').trim().length > 0;
  const hasReasoning = (msg.reasoning || '').trim().length > 0;
  const actionsDisabled = state.isGenerating;
  const disabledAttr = actionsDisabled ? ' disabled' : '';
  const disabledClass = actionsDisabled ? ' is-disabled' : '';

  let html = `<div class="msg msg-assistant" data-id="${msg.id}">`;

  // Loading spinner
  if (isStreaming && !hasContent && !hasReasoning) {
    html += '<div class="msg-loading"><div class="spinner"></div><span>思考中...</span></div>';
  }

  // Reasoning block
  if (hasReasoning) {
    const timeStr = msg.reasoningTimeMs ? (msg.reasoningTimeMs / 1000).toFixed(1) : '...';
    html += `<div class="reasoning-block">
      <div class="reasoning-toggle" onclick="toggleReasoning(this)">
        <span class="arrow">▶</span>
        <span>已思考 ${timeStr} 秒</span>
      </div>
      <div class="reasoning-content">${escHtml(msg.reasoning)}</div>
    </div>`;
  }

  // Message content
  if (hasContent) {
    // 正文放入独立 Shadow DOM 容器，避免消息内 style 污染操作按钮与全局 UI。
    html += `<div class="msg-content-host" data-shadow-msg-id="${msg.id}"></div>`;
  }

  // Tool logs
  if (msg.toolLogs && msg.toolLogs.length > 0) {
    html += '<div class="tool-logs">';
    for (const log of msg.toolLogs) {
      const logIcon = log.status === 'success' ? '✓' : (log.status === 'error' ? '✗' : '○');
      const cls = log.status === 'success' ? 'success' : (log.status === 'error' ? 'error' : '');
      html += `<div class="tool-log-item">
        <span class="tool-log-icon ${cls}">${logIcon}</span>
        <span>${escHtml(log.toolName)}: ${escHtml(log.summary)}</span>
      </div>`;
    }
    html += '</div>';
  }

  // Action buttons (only when not streaming)
  if (!isStreaming) {
    html += '<div class="msg-actions">';
    if (msg.isLast) {
      html += `<button class="${disabledClass}" onclick="Bridge.onMessageAction(${msg.id},'resend')" title="重发"${disabledAttr}>${icon('refresh')}</button>`;
    }
    if (msg.canContinue) {
      html += `<button class="continue-btn${disabledClass}" onclick="Bridge.onMessageAction(${msg.id},'continue')" title="继续"${disabledAttr}>${icon('play_arrow')}<span class="continue-text">继续</span></button>`;
    }
    html += '<span class="spacer"></span>';
    html += `<button class="${disabledClass}" onclick="Bridge.onMessageAction(${msg.id},'edit')" title="编辑"${disabledAttr}>${icon('edit')}</button>`;
    html += `<button class="${disabledClass}" onclick="Bridge.onMessageAction(${msg.id},'copy')" title="复制"${disabledAttr}>${icon('content_copy')}</button>`;
    html += `<button class="${disabledClass}" onclick="Bridge.onMessageAction(${msg.id},'more')" title="更多"${disabledAttr}>${icon('more_horiz')}</button>`;
    html += '</div>';
  }

  html += '</div>';
  return html;
}

/** 增量更新单条消息 DOM（流式场景优化，避免全量重绘） */
function updateMessageDOM(msg) {
  const el = $list.querySelector(`.msg[data-id="${msg.id}"]`);
  if (!el) {
    // 消息不在 DOM 中，追加
    const wasAtBottom = isNearBottom();
    $list.insertAdjacentHTML('beforeend', renderMessage(msg));
    mountAssistantShadowContent(msg.id, $list);
    if (wasAtBottom) scrollToBottom(false);
    return;
  }
  // 保存 reasoning 展开状态
  const reasoningOpen = !!el.querySelector('.reasoning-content.open');
  // 替换整个消息节点内容
  const temp = document.createElement('div');
  temp.innerHTML = renderMessage(msg);
  const newEl = temp.firstElementChild;
  el.replaceWith(newEl);
  mountAssistantShadowContent(msg.id, newEl);
  // 恢复 reasoning 展开状态
  if (reasoningOpen) {
    const arrow = newEl.querySelector('.reasoning-toggle .arrow');
    const content = newEl.querySelector('.reasoning-content');
    if (arrow) arrow.classList.add('open');
    if (content) content.classList.add('open');
  }
}
