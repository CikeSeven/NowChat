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
};

// ===== DOM refs =====
let $list, $input, $sendBtn, $attachPreview, $scrollFab, $streamCheck, $modelName;

// ===== Init =====
document.addEventListener('DOMContentLoaded', () => {
  $list = document.getElementById('message-list');
  $input = document.getElementById('msg-input');
  $sendBtn = document.getElementById('send-btn');
  $attachPreview = document.getElementById('attachment-preview');
  $scrollFab = document.getElementById('scroll-to-bottom');
  $streamCheck = document.getElementById('stream-check');
  $modelName = document.getElementById('model-name');

  // 自动增高 textarea
  $input.addEventListener('input', autoResize);

  // 发送
  $sendBtn.addEventListener('click', handleSend);
  $input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
      e.preventDefault();
      handleSend();
    }
  });

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
  addBtn.innerHTML = SVG_ADD_CIRCLE;
  addBtn.addEventListener('click', () => {
    Bridge.onShowAttachmentMenu();
  });

  // 配置 marked
  setupMarked();

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

  // 图片点击
  renderer.image = function(href, title, text) {
    if (typeof href === 'object') { title = href.title; text = href.text; href = href.href; }
    return `<img src="${escHtml(href)}" alt="${escHtml(text || '')}" title="${escHtml(title || '')}" onclick="Bridge.onImageTap('${escJs(href)}')" />`;
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

// ===== DOM 渲染 =====

/** 完整重绘消息列表 */
function renderAllMessages() {
  const wasAtBottom = isNearBottom();
  let html = '';

  if (state.systemPrompt) {
    html += `<div class="system-prompt-item">
      <span class="prompt-chip" onclick="Bridge.onMessageAction(0,'editSystemPrompt')">${escHtml(truncate(state.systemPrompt, 60))}</span>
    </div>`;
  }

  if (state.isLoadingMore) {
    html += '<div class="loading-more"><div class="spinner"></div></div>';
  }

  if (state.messages.length === 0 && !state.isLoadingMore) {
    html += '<div class="empty-state"><span>发送消息以开始新的会话</span></div>';
  }

  for (const msg of state.messages) {
    html += renderMessage(msg);
  }

  $list.innerHTML = html;
  if (wasAtBottom) scrollToBottom(false);
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
      if (isImagePath(p) || p.startsWith('data:image/')) {
        return `<img src="${escHtml(p)}" onclick="Bridge.onImageTap('${escJs(p)}')" />`;
      }
      return `<span class="file-chip">${escHtml(fileName(p))}</span>`;
    }).join('');
    attachHtml = `<div class="msg-attachments">${items}</div>`;
  }
  return `<div class="msg msg-user" data-id="${msg.id}">
    <div class="msg-bubble" ontouchstart="startLongPress(event, ${msg.id})" ontouchend="cancelLongPress()" ontouchcancel="cancelLongPress()" oncontextmenu="handleContextMenu(event, ${msg.id})">${escHtml(msg.content)}${attachHtml}</div>
  </div>`;
}

function renderAssistantMessage(msg) {
  const isStreaming = msg.isStreaming;
  const hasContent = (msg.content || '').trim().length > 0;
  const hasReasoning = (msg.reasoning || '').trim().length > 0;

  let html = `<div class="msg msg-assistant" data-id="${msg.id}" ontouchstart="startLongPress(event, ${msg.id}, 'assistant')" ontouchend="cancelLongPress()" ontouchcancel="cancelLongPress()" oncontextmenu="handleContextMenu(event, ${msg.id}, 'assistant')">`;

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
    html += `<div class="msg-content">${renderMarkdown(msg.content)}</div>`;
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
      html += `<button onclick="Bridge.onMessageAction(${msg.id},'resend')" title="重发">${SVG_REFRESH}</button>`;
    }
    if (msg.canContinue) {
      html += `<button onclick="Bridge.onMessageAction(${msg.id},'continue')" title="继续">${SVG_PLAY}</button>`;
    }
    html += `<span class="spacer"></span>`;
    html += `<button onclick="Bridge.onMessageAction(${msg.id},'edit')" title="编辑">${SVG_EDIT}</button>`;
    html += `<button onclick="Bridge.onMessageAction(${msg.id},'copy')" title="复制">${SVG_COPY}</button>`;
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
    el || $list.insertAdjacentHTML('beforeend', renderMessage(msg));
    if (wasAtBottom) scrollToBottom(false);
    return;
  }
  // 替换整个消息节点内容
  const temp = document.createElement('div');
  temp.innerHTML = renderMessage(msg);
  const newEl = temp.firstElementChild;
  el.replaceWith(newEl);
}

// ===== Flutter → JS API (window.ChatBridge) =====
window.ChatBridge = {
  /** 添加一条消息 */
  addMessage(jsonStr) {
    const msg = JSON.parse(jsonStr);
    state.messages.push(msg);
    const wasAtBottom = isNearBottom();
    $list.insertAdjacentHTML('beforeend', renderMessage(msg));
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
    state.model = name || '';
    state.modelSupportsVision = supportsVision;
    state.modelSupportsTools = supportsTools;
    $modelName.textContent = name || '选择模型';
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
    $sendBtn.innerHTML = SVG_STOP;
    $sendBtn.title = '打断生成';
  } else if (hasContent && hasModel) {
    $sendBtn.className = 'can-send';
    $sendBtn.innerHTML = SVG_SEND;
    $sendBtn.title = '发送消息';
  } else {
    $sendBtn.className = 'disabled';
    $sendBtn.innerHTML = SVG_SEND;
    $sendBtn.title = '发送消息';
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
      return `<div class="att-item">
        <img class="att-img" src="${escHtml(p)}" />
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
    if (role === 'assistant') {
      Bridge.onMessageAction(id, 'longpress');
    } else {
      Bridge.onUserMessageLongPress(id);
    }
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
  if (role === 'assistant') {
    Bridge.onMessageAction(id, 'longpress');
  } else {
    Bridge.onUserMessageLongPress(id);
  }
}

function copyMessageContent(id) {
  Bridge.onMessageAction(id, 'copy');
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
  const lower = path.toLowerCase();
  return /\.(png|jpg|jpeg|webp|gif|bmp|heic|heif)$/.test(lower);
}

// ===== SVG Icons =====
const SVG_SEND = `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="22" y1="2" x2="11" y2="13"/><polygon points="22 2 15 22 11 13 2 9 22 2"/></svg>`;
const SVG_STOP = `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><rect x="9" y="9" width="6" height="6" rx="1"/></svg>`;
const SVG_REFRESH = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17.65 6.35A7.958 7.958 0 0 0 12 4C7.58 4 4.01 7.58 4.01 12S7.58 20 12 20c3.73 0 6.84-2.55 7.73-6h-2.08A5.99 5.99 0 0 1 12 18c-3.31 0-6-2.69-6-6s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z"/></svg>`;
const SVG_PLAY = `<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>`;
const SVG_EDIT = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>`;
const SVG_COPY = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>`;
const SVG_ADD_CIRCLE = `<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="16"/><line x1="8" y1="12" x2="16" y2="12"/></svg>`;
