/**
 * chat.js - 消息渲染引擎
 *
 * 使用 marked.js 渲染 Markdown，highlight.js 代码高亮，KaTeX 数学公式。
 * Flutter 侧通过 window.ChatBridge.xxx() 调用此处暴露的方法。
 */

// ===== State =====
const state = {
  messages: [],           // { id, role, content, reasoning, reasoningTimeMs, imagePaths, toolLogs, isStreaming }
  isGenerating: false,
  systemPrompt: '',
  attachments: [],        // 输入框附件路径
  model: '',
  modelSupportsVision: false,
  modelSupportsTools: false,
  isStreaming: true,
  streamingSupported: true,
  isLoadingMore: false,
  _scrollLock: false,     // 防止滚动事件重入
  imageProxyBase: '',     // 本地图片代理服务器 base URL
};

// ===== DOM refs =====
let $list, $input, $sendBtn, $attachPreview, $scrollFab, $streamCheck, $modelName, $modelCaps;

// ===== Init =====
document.addEventListener('DOMContentLoaded', () => {
  $list = document.getElementById('message-list');
  $input = document.getElementById('msg-input');
  $sendBtn = document.getElementById('send-btn');
  $attachPreview = document.getElementById('attachment-preview');
  $scrollFab = document.getElementById('scroll-to-bottom');
  $streamCheck = document.getElementById('stream-check');
  $modelName = document.getElementById('model-name');
  $modelCaps = document.getElementById('model-caps');

  // 自动增高 textarea
  $input.addEventListener('input', autoResize);

  // 发送
  $sendBtn.addEventListener('click', handleSend);

  // 滚动监听
  $list.addEventListener('scroll', handleScroll);

  // 滚到底部按钮
  $scrollFab.addEventListener('click', () => scrollToBottom(true));

  // 流式开关
  $streamCheck.addEventListener('change', () => {
    state.isStreaming = $streamCheck.checked;
    Bridge.onToggleStreaming($streamCheck.checked);
  });

  // 模型选择
  document.getElementById('model-selector').addEventListener('click', () => {
    Bridge.onSelectModel();
  });

  // 附件按钮
  const addBtn = document.getElementById('add-btn');
  addBtn.innerHTML = icon('add');
  addBtn.addEventListener('click', () => {
    Bridge.onShowAttachmentMenu();
  });

  // 配置 marked
  setupMarked();
  if ($modelCaps) {
    $modelCaps.innerHTML = '';
  }

  Bridge.onReady();
});

// ===== Marked 配置 =====
function setupMarked() {
  const renderer = new marked.Renderer();

  // 代码块：包裹 header + highlight
  renderer.code = function(code, lang) {
    // marked v14+ passes an object; v4 passes (code, lang)
    if (typeof code === 'object') { lang = code.lang; code = code.text; }
    const language = lang && hljs.getLanguage(lang) ? lang : 'plaintext';
    const label = lang || 'code';
    let highlighted;
    try {
      highlighted = hljs.highlight(code, { language }).value;
    } catch (_) {
      highlighted = hljs.highlightAuto(code).value;
    }
    return `<div class="code-block-wrapper">
      <div class="code-block-header">
        <span>${escHtml(label)}</span>
        <button class="copy-btn" onclick="copyCode(this)">复制</button>
      </div>
      <pre><code class="hljs language-${escHtml(language)}">${highlighted}</code></pre>
    </div>`;
  };

  // 图片点击 — 本地路径自动走代理
  renderer.image = function(href, title, text) {
    if (typeof href === 'object') { title = href.title; text = href.text; href = href.href; }
    const src = proxyImageUrl(href);
    return `<img src="${escHtml(src)}" alt="${escHtml(text || '')}" title="${escHtml(title || '')}" onclick="Bridge.onImageTap('${escJs(href)}')" />`;
  };

  // 链接拦截
  renderer.link = function(href, title, text) {
    if (typeof href === 'object') { title = href.title; text = href.text; href = href.href; }
    return `<a href="javascript:void(0)" onclick="Bridge.onLinkTap('${escJs(href)}')" title="${escHtml(title || '')}">${text}</a>`;
  };

  marked.setOptions({
    renderer,
    gfm: true,
    breaks: true,
  });
}

// ===== Markdown 渲染（含 LaTeX 处理）=====
function renderMarkdown(text) {
  if (!text) return '';
  // 先保护 LaTeX 块，避免 marked 破坏
  const blocks = [];
  // $$...$$ 块级
  text = text.replace(/\$\$([\s\S]+?)\$\$/g, (_, tex) => {
    const idx = blocks.length;
    blocks.push({ tex, display: true });
    return `%%LATEX_BLOCK_${idx}%%`;
  });
  // $...$ 行内（不匹配 $$）
  text = text.replace(/(?<!\$)\$(?!\$)(.+?)(?<!\$)\$(?!\$)/g, (_, tex) => {
    const idx = blocks.length;
    blocks.push({ tex, display: false });
    return `%%LATEX_INLINE_${idx}%%`;
  });

  let html = marked.parse(text);

  // 还原 LaTeX
  html = html.replace(/%%LATEX_BLOCK_(\d+)%%/g, (_, i) => {
    const b = blocks[parseInt(i)];
    try {
      return katex.renderToString(b.tex, { displayMode: true, throwOnError: false });
    } catch (e) {
      return `<code>${escHtml(b.tex)}</code>`;
    }
  });
  html = html.replace(/%%LATEX_INLINE_(\d+)%%/g, (_, i) => {
    const b = blocks[parseInt(i)];
    try {
      return katex.renderToString(b.tex, { displayMode: false, throwOnError: false });
    } catch (e) {
      return `<code>${escHtml(b.tex)}</code>`;
    }
  });

  return html;
}

/**
 * Assistant 消息正文的 Shadow DOM 样式。
 *
 * 说明：
 * - 将正文渲染在独立 ShadowRoot 中，阻断消息内 style 对全局按钮的污染。
 * - 只保留正文相关样式，消息操作按钮仍由主文档样式控制。
 */
const ASSISTANT_SHADOW_STYLE = `
:host {
  display: block;
  max-width: 100%;
  contain: layout paint style;
}
*, *::before, *::after { box-sizing: border-box; }

.md-root {
  line-height: 1.65;
  color: var(--on-surface);
  word-break: break-word;
  overflow-wrap: anywhere;
}

.md-root h1 { font-size: 1.4em; font-weight: 700; margin: 12px 0 6px; }
.md-root h2 { font-size: 1.25em; font-weight: 700; margin: 10px 0 5px; }
.md-root h3 { font-size: 1.1em; font-weight: 600; margin: 8px 0 4px; }
.md-root h4, .md-root h5, .md-root h6 { font-size: 1em; font-weight: 600; margin: 6px 0 3px; }

.md-root p { margin: 4px 0; }
.md-root ul, .md-root ol { padding-left: 20px; margin: 4px 0; }
.md-root li { margin: 2px 0; }

.md-root blockquote {
  border-left: 3px solid var(--md-blockquote-border, var(--blockquote-border));
  padding: 4px 12px;
  margin: 6px 0;
  color: var(--on-surface-variant);
  background: var(--md-blockquote-bg, var(--surface-container));
  border-radius: 0 8px 8px 0;
}

.md-root hr {
  border: none;
  height: 1px;
  background: linear-gradient(to right, transparent, var(--md-hr, var(--outline-variant)), transparent);
  margin: 10px 0;
}

.md-root a {
  color: var(--md-link, var(--primary));
  text-decoration: underline;
  text-decoration-color: var(--md-link-underline, var(--primary));
  text-decoration-thickness: 1.4px;
  text-underline-offset: 2px;
}

.md-root a:hover {
  text-decoration: underline;
}

.md-root img {
  max-width: 100%;
  height: auto;
  border-radius: 8px;
  cursor: pointer;
  margin: 4px 0;
}

.md-root code:not(pre code) {
  background: var(--md-inline-code-bg, var(--primary-container));
  color: var(--md-inline-code-color, var(--on-primary-container));
  padding: 1px 5px;
  border-radius: 4px;
  font-size: 0.9em;
  font-family: "SF Mono", "Fira Code", "Cascadia Code", monospace;
}

.code-block-wrapper {
  position: relative;
  margin: 8px 0;
  border-radius: 10px;
  overflow: hidden;
  background: var(--md-codeblock-bg, var(--code-bg));
  border: 1px solid var(--md-codeblock-border, var(--outline-variant));
  max-width: 100%;
}

.code-block-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 4px 12px;
  background: var(--md-code-header-bg, var(--surface-container-high));
  font-size: 12px;
  color: var(--on-surface-variant);
}

.code-block-header .copy-btn {
  background: none;
  border: none;
  color: var(--on-surface-variant);
  cursor: pointer;
  font-size: 12px;
  padding: 2px 6px;
  border-radius: 4px;
}

.code-block-header .copy-btn:active {
  background: var(--outline-variant);
}

.code-block-wrapper pre {
  margin: 0;
  padding: 12px;
  overflow-x: auto;
  font-size: 13px;
  line-height: 1.45;
  font-family: "SF Mono", "Fira Code", "Cascadia Code", monospace;
}

.code-block-wrapper pre code {
  font-family: inherit;
}

.md-root table {
  border-collapse: collapse;
  margin: 8px 0;
  width: 100%;
  display: block;
  overflow-x: auto;
  font-size: 14px;
}

.md-root th, .md-root td {
  border: 1px solid var(--md-table-border, var(--outline-variant));
  padding: 6px 10px;
  text-align: left;
}

.md-root th {
  background: var(--surface-container-high);
  font-weight: 600;
}

.katex-display {
  overflow-x: auto;
  overflow-y: hidden;
  padding: 4px 0;
}
`;

/** 返回指定消息的 assistant 正文 host 选择器。 */
function shadowHostSelector(messageId) {
  return `.msg-content-host[data-shadow-msg-id="${messageId}"]`;
}

/** 在消息正文 host 上挂载 Shadow DOM 内容。 */
function mountAssistantShadowContent(messageId, root = document) {
  const msg = state.messages.find(m => m.id === messageId);
  if (!msg || msg.role !== 'assistant') return;
  const host = root.querySelector ? root.querySelector(shadowHostSelector(messageId)) : null;
  if (!host) return;

  const html = renderMarkdown(msg.content || '');
  if (!host.shadowRoot) {
    host.attachShadow({ mode: 'open' });
  }
  host.shadowRoot.innerHTML = `<style>${ASSISTANT_SHADOW_STYLE}</style><div class="md-root">${html}</div>`;
}

/** 批量挂载当前容器中的 assistant 正文 Shadow DOM。 */
function mountAllAssistantShadowContents(root = document) {
  if (!root || !root.querySelectorAll) return;
  const hosts = root.querySelectorAll('.msg-content-host[data-shadow-msg-id]');
  for (const host of hosts) {
    const rawId = host.getAttribute('data-shadow-msg-id') || '';
    const id = parseInt(rawId, 10);
    if (!Number.isFinite(id)) continue;
    mountAssistantShadowContent(id, root);
  }
}

// ===== DOM 渲染 =====

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
    const items = msg.imagePaths.map(p => {
      if (isRenderableImageAttachment(p)) {
        const src = proxyImageUrl(p);
        return `<img src="${escHtml(src)}" onclick="Bridge.onImageTap('${escJs(p)}')" />`;
      }
      return `<span class="file-chip">${escHtml(fileName(p))}</span>`;
    }).join('');
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
      const icon = log.status === 'success' ? '✓' : (log.status === 'error' ? '✗' : '○');
      const cls = log.status === 'success' ? 'success' : (log.status === 'error' ? 'error' : '');
      html += `<div class="tool-log-item">
        <span class="tool-log-icon ${cls}">${icon}</span>
        <span>${escHtml(log.toolName)}: ${escHtml(log.summary)}</span>
      </div>`;
    }
    html += '</div>';
  }

  // Action buttons (only when not streaming)
  if (!isStreaming) {
    html += `<div class="msg-actions">`;
    if (msg.isLast) {
      html += `<button class="${disabledClass}" onclick="Bridge.onMessageAction(${msg.id},'resend')" title="重发"${disabledAttr}>${icon('refresh')}</button>`;
    }
    if (msg.canContinue) {
      html += `<button class="${disabledClass}" onclick="Bridge.onMessageAction(${msg.id},'continue')" title="继续"${disabledAttr}>${icon('play_arrow')}</button>`;
    }
    html += `<span class="spacer"></span>`;
    html += `<button class="${disabledClass}" onclick="Bridge.onMessageAction(${msg.id},'edit')" title="编辑"${disabledAttr}>${icon('edit')}</button>`;
    html += `<button class="${disabledClass}" onclick="Bridge.onMessageAction(${msg.id},'copy')" title="复制"${disabledAttr}>${icon('content_copy')}</button>`;
    html += `<button class="${disabledClass}" onclick="Bridge.onMessageAction(${msg.id},'more')" title="更多"${disabledAttr}>${icon('more_horiz')}</button>`;
    html += `</div>`;
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
    const msg = state.messages.find(m => m.id === id);
    if (!msg) return;
    msg.content = content;
    updateMessageDOM(msg);
    if (isNearBottom()) scrollToBottom(false);
  },

  /** 更新思考内容（流式追加） */
  updateThinkingContent(id, content, timeMs) {
    const msg = state.messages.find(m => m.id === id);
    if (!msg) return;
    msg.reasoning = content;
    if (timeMs !== undefined) msg.reasoningTimeMs = timeMs;
    updateMessageDOM(msg);
    if (isNearBottom()) scrollToBottom(false);
  },

  /** 标记消息流式结束 */
  endStreaming(id, canContinue) {
    const msg = state.messages.find(m => m.id === id);
    if (!msg) return;
    msg.isStreaming = false;
    msg.canContinue = !!canContinue;
    updateMessageDOM(msg);
  },

  /** 删除消息 */
  deleteMessage(id) {
    const idx = state.messages.findIndex(m => m.id === id);
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
    const msg = state.messages.find(m => m.id === messageId);
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

// ===== 输入处理 =====
function handleSend() {
  if (state.isGenerating) {
    Bridge.onStopGenerating();
    return;
  }
  const text = $input.value.trim();
  if (!text && state.attachments.length === 0) return;
  if (!state.model) return;
  Bridge.onSendMessage(text);
  $input.value = '';
  autoResize();
  updateSendButton();
}

function autoResize() {
  $input.style.height = 'auto';
  $input.style.height = Math.min($input.scrollHeight, 120) + 'px';
  updateSendButton();
}

function updateSendButton() {
  const hasContent = $input.value.trim().length > 0 || state.attachments.length > 0;
  const hasModel = !!state.model;
  $sendBtn.className = '';
  if (state.isGenerating) {
    $sendBtn.className = 'generating';
    $sendBtn.innerHTML = icon('stop_circle');
    $sendBtn.title = '打断生成';
  } else if (hasContent && hasModel) {
    $sendBtn.className = 'can-send';
    $sendBtn.innerHTML = icon('send');
    $sendBtn.title = '发送消息';
  } else {
    $sendBtn.className = 'disabled';
    $sendBtn.innerHTML = icon('send');
    $sendBtn.title = '发送消息';
  }
}

/** 根据全局生成状态，批量更新消息区操作按钮可用性。 */
function refreshMessageActionButtonsState() {
  const buttons = $list ? $list.querySelectorAll('.msg-actions button') : [];
  for (const btn of buttons) {
    if (state.isGenerating) {
      btn.disabled = true;
      btn.classList.add('is-disabled');
    } else {
      btn.disabled = false;
      btn.classList.remove('is-disabled');
    }
  }
}

function renderAttachments() {
  if (!$attachPreview) return;
  if (state.attachments.length === 0) {
    $attachPreview.innerHTML = '';
    return;
  }
  $attachPreview.innerHTML = state.attachments.map(p => {
    if (isImagePath(p)) {
      const src = proxyImageUrl(p);
      return `<div class="att-item">
        <img class="att-img" src="${escHtml(src)}" />
        <button class="att-remove" onclick="Bridge.onRemoveAttachment('${escJs(p)}')">×</button>
      </div>`;
    }
    return `<div class="att-item">
      <span class="att-file">${escHtml(fileName(p))}</span>
      <button class="att-remove" onclick="Bridge.onRemoveAttachment('${escJs(p)}')">×</button>
    </div>`;
  }).join('');
}

// ===== 滚动处理 =====
function handleScroll() {
  if (state._scrollLock) return;
  // 显示/隐藏滚到底部按钮
  if (isNearBottom()) {
    $scrollFab.classList.remove('visible');
  } else {
    $scrollFab.classList.add('visible');
  }
  // 接近顶部时触发加载更多
  if ($list.scrollTop < 80 && !state.isLoadingMore) {
    state._scrollLock = true;
    Bridge.onScrollNearTop();
    setTimeout(() => { state._scrollLock = false; }, 500);
  }
}

function isNearBottom() {
  if (!$list) return true;
  return ($list.scrollHeight - $list.scrollTop - $list.clientHeight) < 150;
}

function scrollToBottom(animated) {
  if (!$list) return;
  if (animated) {
    $list.scrollTo({ top: $list.scrollHeight, behavior: 'smooth' });
  } else {
    $list.scrollTop = $list.scrollHeight;
  }
  $scrollFab.classList.remove('visible');
}

// ===== 工具函数 =====
function toggleReasoning(el) {
  const arrow = el.querySelector('.arrow');
  const content = el.nextElementSibling;
  arrow.classList.toggle('open');
  content.classList.toggle('open');
}

function copyCode(btn) {
  const pre = btn.closest('.code-block-wrapper').querySelector('pre code');
  if (!pre) return;
  navigator.clipboard.writeText(pre.textContent).then(() => {
    btn.textContent = '已复制';
    setTimeout(() => { btn.textContent = '复制'; }, 1500);
  });
}

// ===== Long press detection =====
let _longPressTimer = null;

function startLongPress(event, id, role) {
  cancelLongPress();
  _longPressTimer = setTimeout(() => {
    _longPressTimer = null;
    Bridge.onUserMessageLongPress(id);
  }, 500);
}

function cancelLongPress() {
  if (_longPressTimer) {
    clearTimeout(_longPressTimer);
    _longPressTimer = null;
  }
}

function handleContextMenu(event, id, role) {
  event.preventDefault();
  Bridge.onUserMessageLongPress(id);
}

function copyMessageContent(id) {
  Bridge.onMessageAction(id, 'copy');
}

/** 渲染模型能力图标（视觉/工具）。 */
function renderModelCapabilityBadges(supportsVision, supportsTools, hasModel) {
  if (!hasModel) return '';
  const caps = [];
  if (supportsVision) {
    caps.push(
      `<span class="ms-icon model-cap" title="支持视觉">visibility</span>`,
    );
  }
  if (supportsTools) {
    caps.push(
      `<span class="ms-icon model-cap" title="支持工具">build</span>`,
    );
  }
  return caps.join('');
}

function escHtml(str) {
  if (!str) return '';
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function escJs(str) {
  if (!str) return '';
  return str.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, '\\n');
}

function truncate(str, max) {
  if (!str || str.length <= max) return str;
  return str.substring(0, max) + '...';
}

function fileName(path) {
  const normalized = path.replace(/\\/g, '/');
  const idx = normalized.lastIndexOf('/');
  return idx === -1 ? normalized : normalized.substring(idx + 1);
}

function isImagePath(path) {
  if (!path) return false;
  const lower = path.toLowerCase();
  const pure = lower.split('?')[0].split('#')[0];
  return /\.(png|jpg|jpeg|webp|gif|bmp|heic|heif)$/.test(pure);
}

/** 判断附件是否应按图片渲染，避免普通文件误渲染成破图。 */
function isRenderableImageAttachment(path) {
  if (!path) return false;
  const lower = path.toLowerCase();
  if (/^data:image\//i.test(lower)) return true;
  if (isImagePath(path)) return true;
  if (!/^https?:\/\//i.test(path)) return false;
  try {
    const url = new URL(path);
    if (url.pathname === '/local-image') return true;
    return isImagePath(url.pathname);
  } catch (_) {
    return false;
  }
}

/** 将本地文件路径转为代理 URL（如果代理服务器可用） */
function proxyImageUrl(path) {
  if (!path) return path;
  // 已经是 http/https/data URI，不处理
  if (/^(https?:|data:)/i.test(path)) return path;
  // 仅图片路径走代理，避免普通文件被误包装成图片 URL。
  if (!isImagePath(path)) return path;
  // 本地路径（以 / 开头或包含盘符如 C:\）走代理
  if (
    state.imageProxyBase &&
    (path.startsWith('/') || path.startsWith('file://') || /^[a-zA-Z]:/.test(path))
  ) {
    return state.imageProxyBase + '/local-image?path=' + encodeURIComponent(path);
  }
  return path;
}

// ===== Material Symbols icon helper =====
function icon(name, extraClass = '') {
  const cls = extraClass ? `ms-icon ${extraClass}` : 'ms-icon';
  return `<span class="${cls}" aria-hidden="true">${name}</span>`;
}
