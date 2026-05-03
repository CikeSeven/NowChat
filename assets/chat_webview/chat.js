/**
 * chat.js - 运行时 bundle 入口
 *
 * 该文件由 assets/chat_webview/js/*.js 按顺序拼接生成，
 * 供 Flutter WebView 稳定内联加载。
 */

/**
 * state.js
 *
 * 仅负责聊天 WebView 的全局状态与核心 DOM 引用声明。
 * 其它模块通过这些全局变量协作，避免在单文件中混合状态与行为。
 */

// ===== State =====
const state = {
  // { id, role, content, reasoning, reasoningTimeMs, imagePaths, toolLogs, isStreaming }
  messages: [],
  isGenerating: false,
  systemPrompt: '',
  attachments: [], // 输入框附件路径
  model: '',
  modelSupportsVision: false,
  modelSupportsTools: false,
  isStreaming: true,
  streamingSupported: true,
  isLoadingMore: false,
  _scrollLock: false, // 防止滚动事件重入
  imageProxyBase: '', // 本地图片代理服务器 base URL
  streamingMarkdownSnapshots: {}, // messageId -> 流式阶段最近一次完整 Markdown 快照
};

// ===== DOM refs =====
let $list;
let $input;
let $sendBtn;
let $attachPreview;
let $scrollFab;
let $streamCheck;
let $modelName;
let $modelCaps;

/**
 * utils.js
 *
 * 放置通用工具方法：
 * - 字符串转义
 * - 图标渲染
 * - 路径与图片判定
 * - 本地图片代理 URL 生成
 */

function escHtml(str) {
  if (!str) return '';
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function escJs(str) {
  if (!str) return '';
  return str
    .replace(/\\/g, '\\\\')
    .replace(/'/g, "\\'")
    .replace(/\n/g, '\\n');
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
    return `${state.imageProxyBase}/local-image?path=${encodeURIComponent(path)}`;
  }
  return path;
}

// ===== Material Symbols icon helper =====
function icon(name, extraClass = '') {
  const cls = extraClass ? `ms-icon ${extraClass}` : 'ms-icon';
  return `<span class="${cls}" aria-hidden="true">${name}</span>`;
}

/**
 * markdown_renderer.js
 *
 * 负责 Markdown 渲染相关能力：
 * - marked/highlight/katex 配置
 * - Assistant 正文 Shadow DOM 样式隔离
 * - Shadow DOM 挂载与批量更新
 */

// ===== Marked 配置 =====
function setupMarked() {
  const renderer = new marked.Renderer();

  // 代码块：包裹 header + highlight
  renderer.code = function (code, lang) {
    // marked v14+ passes an object; v4 passes (code, lang)
    if (typeof code === 'object') {
      lang = code.lang;
      code = code.text;
    }
    const rawLang = (lang || '').toString();
    const normalizedLang = rawLang.trim().toLowerCase();
    const language =
      normalizedLang && hljs.getLanguage(normalizedLang)
        ? normalizedLang
        : 'plaintext';
    const label = rawLang || 'code';
    const showPreview = canPreviewCodeLanguage(normalizedLang);
    const previewBtn = showPreview
      ? `<button class="preview-btn" onclick="previewCode(this)" title="预览代码">${icon('visibility')}</button>`
      : '';
    let highlighted;
    try {
      highlighted = hljs.highlight(code, { language }).value;
    } catch (_) {
      highlighted = hljs.highlightAuto(code).value;
    }
    return `<div class="code-block-wrapper" data-code-lang="${escHtml(normalizedLang)}">
      <div class="code-block-header">
        <span>${escHtml(label)}</span>
        <span class="code-block-actions">${previewBtn}<button class="copy-btn" onclick="copyCode(this)" title="复制代码">${icon('content_copy')}</button></span>
      </div>
      <pre><code class="hljs language-${escHtml(language)}">${highlighted}</code></pre>
    </div>`;
  };

  // 图片点击 — 本地路径自动走代理
  renderer.image = function (href, title, text) {
    if (typeof href === 'object') {
      title = href.title;
      text = href.text;
      href = href.href;
    }
    const src = proxyImageUrl(href);
    return `<img src="${escHtml(src)}" alt="${escHtml(text || '')}" title="${escHtml(title || '')}" onclick="Bridge.onImageTap('${escJs(href)}')" />`;
  };

  // 链接拦截
  renderer.link = function (href, title, text) {
    if (typeof href === 'object') {
      title = href.title;
      text = href.text;
      href = href.href;
    }
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
    const b = blocks[parseInt(i, 10)];
    try {
      return katex.renderToString(b.tex, { displayMode: true, throwOnError: false });
    } catch (e) {
      return `<code>${escHtml(b.tex)}</code>`;
    }
  });
  html = html.replace(/%%LATEX_INLINE_(\d+)%%/g, (_, i) => {
    const b = blocks[parseInt(i, 10)];
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

.ms-icon {
  font-family: "Material Symbols Rounded";
  font-weight: normal;
  font-style: normal;
  font-size: 28px;
  line-height: 1;
  letter-spacing: normal;
  text-transform: none;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  white-space: nowrap;
  word-wrap: normal;
  direction: ltr;
  -webkit-font-smoothing: antialiased;
  font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 24;
}

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
  font-size: 14px;
  font-weight: 600;
  color: var(--on-surface-variant);
}

.code-block-header .code-block-actions {
  display: inline-flex;
  align-items: center;
  gap: 4px;
}

.code-block-header .preview-btn,
.code-block-header .copy-btn {
  background: none;
  border: none;
  color: var(--on-surface-variant);
  cursor: pointer;
  width: 28px;
  height: 28px;
  padding: 0;
  border-radius: 6px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

.code-block-header .preview-btn .ms-icon,
.code-block-header .copy-btn .ms-icon {
  font-size: 20px;
}

.code-block-header .preview-btn:active,
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

const STREAMING_MARKDOWN_MIN_INTERVAL_MS = 420;
const STREAMING_MARKDOWN_CHAR_THRESHOLD = 180;

/** 判断流式正文是否需要刷新完整 Markdown 快照。 */
function shouldRefreshStreamingMarkdownSnapshot(msg, previous) {
  if (!msg.isStreaming) return true;
  if (!previous) return true;
  const content = msg.content || '';
  if (content.length < previous.length) return true;
  if (content.length - previous.length >= STREAMING_MARKDOWN_CHAR_THRESHOLD) {
    return true;
  }
  const elapsed = Date.now() - previous.updatedAt;
  if (elapsed >= STREAMING_MARKDOWN_MIN_INTERVAL_MS) return true;
  const tail = content.substring(previous.length);
  // 换行或代码围栏变化时刷新快照，避免流式 Markdown 结构长期不完整。
  return tail.includes('\n') || tail.includes('```');
}

/** 生成流式阶段的 Markdown 快照与纯文本尾巴，降低高频完整解析成本。 */
function renderAssistantContent(msg) {
  const content = msg.content || '';
  if (!msg.isStreaming) {
    delete state.streamingMarkdownSnapshots[msg.id];
    return renderMarkdown(content);
  }

  const previous = state.streamingMarkdownSnapshots[msg.id];
  if (shouldRefreshStreamingMarkdownSnapshot(msg, previous)) {
    state.streamingMarkdownSnapshots[msg.id] = {
      length: content.length,
      html: renderMarkdown(content),
      updatedAt: Date.now(),
    };
    return state.streamingMarkdownSnapshots[msg.id].html;
  }

  const tail = content.substring(previous.length);
  if (!tail) return previous.html;
  // 流式尾巴只做 HTML 转义，等下一次快照或结束时再统一跑 Markdown/highlight/KaTeX。
  return `${previous.html}<span class="streaming-tail">${escHtml(tail)}</span>`;
}

/** 返回指定消息的 assistant 正文 host 选择器。 */
function shadowHostSelector(messageId) {
  return `.msg-content-host[data-shadow-msg-id="${messageId}"]`;
}

/** 在消息正文 host 上挂载 Shadow DOM 内容。 */
function mountAssistantShadowContent(messageId, root = document) {
  const msg = state.messages.find((m) => m.id === messageId);
  if (!msg || msg.role !== 'assistant') return;
  const host = root.querySelector ? root.querySelector(shadowHostSelector(messageId)) : null;
  if (!host) return;

  const html = renderAssistantContent(msg);
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
    // 生成期间隐藏“继续”，避免误触与状态冲突。
    if (msg.canContinue && !actionsDisabled) {
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

/** 仅刷新助手正文 Shadow DOM，避免流式阶段替换整条消息节点。 */
function updateAssistantContentDOM(msg) {
  const host = $list.querySelector(shadowHostSelector(msg.id));
  if (!host) {
    updateMessageDOM(msg);
    return;
  }
  mountAssistantShadowContent(msg.id, $list);
}

/** 仅刷新 reasoning 区块；结构从无到有时退回整条消息更新。 */
function updateReasoningDOM(msg) {
  const el = $list.querySelector(`.msg[data-id="${msg.id}"]`);
  if (!el) return;
  const existing = el.querySelector('.reasoning-block');
  const hasReasoning = (msg.reasoning || '').trim().length > 0;
  if (!existing || !hasReasoning) {
    updateMessageDOM(msg);
    return;
  }
  const timeLabel = existing.querySelector('.reasoning-toggle span:last-child');
  if (timeLabel) {
    const timeStr = msg.reasoningTimeMs ? (msg.reasoningTimeMs / 1000).toFixed(1) : '...';
    timeLabel.textContent = `已思考 ${timeStr} 秒`;
  }
  const content = existing.querySelector('.reasoning-content');
  if (content) content.textContent = msg.reasoning || '';
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

/** 前插历史消息片段，不触碰已存在节点，避免长会话加载更多时整表重绘。 */
function prependMessagesDOM(msgs) {
  if (!msgs || msgs.length === 0) return;
  const oldHeight = $list.scrollHeight;
  let html = '';
  for (const msg of msgs) {
    html += renderMessage(msg);
  }

  const systemPromptCard = $list.querySelector('.system-prompt-card');
  if (systemPromptCard) {
    systemPromptCard.insertAdjacentHTML('afterend', html);
  } else {
    $list.insertAdjacentHTML('afterbegin', html);
  }
  for (const msg of msgs) {
    mountAssistantShadowContent(msg.id, $list);
  }
  const newHeight = $list.scrollHeight;
  $list.scrollTop += newHeight - oldHeight;
}

/**
 * interactions.js
 *
 * 负责输入、滚动、复制、长按等交互行为。
 * 该文件不直接持有业务状态，仅通过 state 与渲染函数协作。
 */

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
  $input.style.height = `${Math.min($input.scrollHeight, 120)}px`;
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
  $attachPreview.innerHTML = state.attachments
    .map((p) => {
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
    })
    .join('');
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
    setTimeout(() => {
      state._scrollLock = false;
    }, 500);
  }
}

function isNearBottom() {
  if (!$list) return true;
  return $list.scrollHeight - $list.scrollTop - $list.clientHeight < 150;
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
  copyTextToClipboard(pre.textContent || '')
    .then(() => {
      btn.innerHTML = icon('check');
      setTimeout(() => {
        btn.innerHTML = icon('content_copy');
      }, 1200);
    })
    .catch(() => {
      // WebView 某些上下文不允许 clipboard API，失败时保留原图标，避免误导。
      btn.innerHTML = icon('content_copy');
    });
}

/** 规范化代码语言标识，统一大小写与前缀差异。 */
function normalizeCodeLanguage(rawLang) {
  return (rawLang || '').toString().trim().toLowerCase().replace(/^language-/, '');
}

/**
 * 代码预览渲染器注册表：
 * - key: 语言名（标准化后）
 * - value: (code, context) => srcdoc 字符串
 */
const _codePreviewRenderers = new Map();

/**
 * 注册代码预览渲染器。
 *
 * 通过 aliases 可以一次注册多个语言别名，避免在判定逻辑里写 if/else。
 */
function registerCodePreviewRenderer(language, renderer, aliases = []) {
  const normalized = normalizeCodeLanguage(language);
  if (!normalized || typeof renderer !== 'function') return false;
  _codePreviewRenderers.set(normalized, renderer);
  for (const alias of aliases) {
    const normalizedAlias = normalizeCodeLanguage(alias);
    if (!normalizedAlias) continue;
    _codePreviewRenderers.set(normalizedAlias, renderer);
  }
  return true;
}

/** 取消某个语言渲染器注册。 */
function unregisterCodePreviewRenderer(language) {
  const normalized = normalizeCodeLanguage(language);
  if (!normalized) return false;
  return _codePreviewRenderers.delete(normalized);
}

/** 获取当前已注册的可预览语言列表（去重、排序）。 */
function getCodePreviewLanguages() {
  return Array.from(new Set(_codePreviewRenderers.keys())).sort();
}

/** 按语言解析预览渲染器。 */
function resolveCodePreviewRenderer(rawLang) {
  const lang = normalizeCodeLanguage(rawLang);
  if (!lang) return null;
  return _codePreviewRenderers.get(lang) || null;
}

/** 判断某语言是否支持预览（由注册表决定，不写死判断）。 */
function canPreviewCodeLanguage(rawLang) {
  return !!resolveCodePreviewRenderer(rawLang);
}

/** 初始化默认预览能力，并允许外部扩展注入。 */
function bootstrapCodePreviewRegistry() {
  if (_codePreviewRenderers.size > 0) return;
  // 默认内置：HTML 直接作为 srcdoc 渲染。
  registerCodePreviewRenderer('html', (code) => code, ['htm']);
  // 允许外部在 window 上注入扩展渲染器（例如插件或后续模块）。
  const external = window.NowChatCodePreviewRenderers;
  if (!Array.isArray(external)) return;
  for (const item of external) {
    if (!item || typeof item !== 'object') continue;
    registerCodePreviewRenderer(item.language, item.render, item.aliases || []);
  }
}

/** 从代码块按钮位置提取语言与源码。 */
function getCodeBlockPayload(btn) {
  const wrapper = btn.closest('.code-block-wrapper');
  if (!wrapper) return null;
  const codeEl = wrapper.querySelector('pre code');
  if (!codeEl) return null;
  return {
    lang: normalizeCodeLanguage(wrapper.getAttribute('data-code-lang') || ''),
    code: codeEl.textContent || '',
  };
}

bootstrapCodePreviewRegistry();

/** 对外暴露预览注册中心，便于后续脚本按需扩展语言支持。 */
window.CodePreviewRegistry = {
  register: registerCodePreviewRenderer,
  unregister: unregisterCodePreviewRenderer,
  list: getCodePreviewLanguages,
};

const _codePreviewState = {
  lang: '',
  code: '',
};

let _codePreviewModal = null;
let _codePreviewFrame = null;

/** 创建（或获取）代码预览弹层。 */
function ensureCodePreviewModal() {
  if (_codePreviewModal) return;
  const modal = document.createElement('div');
  modal.className = 'code-preview-modal';
  modal.innerHTML = `
    <div class="code-preview-card">
      <div class="code-preview-header">
        <span class="code-preview-title">代码预览</span>
        <div class="code-preview-actions">
          <button type="button" class="code-preview-reload" title="刷新预览">${icon('refresh')}</button>
          <button type="button" class="code-preview-close" title="关闭预览">${icon('close')}</button>
        </div>
      </div>
      <iframe class="code-preview-frame" sandbox="allow-scripts allow-forms"></iframe>
    </div>
  `;
  document.body.appendChild(modal);
  _codePreviewModal = modal;
  _codePreviewFrame = modal.querySelector('.code-preview-frame');
  const closeBtn = modal.querySelector('.code-preview-close');
  const reloadBtn = modal.querySelector('.code-preview-reload');
  closeBtn.addEventListener('click', closeCodePreview);
  reloadBtn.addEventListener('click', reloadCodePreview);
  modal.addEventListener('click', (event) => {
    if (event.target === modal) closeCodePreview();
  });
}

/** 为不同语言生成可执行预览文档。 */
function buildPreviewSrcdoc(lang, code) {
  const renderer = resolveCodePreviewRenderer(lang);
  if (!renderer) {
    return `<pre style="padding:12px;font-family:monospace;">暂不支持 ${escHtml(lang || '该语言')} 预览</pre>`;
  }
  try {
    const rendered = renderer(code, {
      language: normalizeCodeLanguage(lang),
      languages: getCodePreviewLanguages(),
    });
    return typeof rendered === 'string' ? rendered : '';
  } catch (e) {
    return `<pre style="padding:12px;font-family:monospace;">预览渲染失败：${escHtml(String(e))}</pre>`;
  }
}

/** 打开代码预览弹层。 */
function openCodePreview(lang, code) {
  ensureCodePreviewModal();
  _codePreviewState.lang = lang;
  _codePreviewState.code = code;
  if (!_codePreviewFrame || !_codePreviewModal) return;
  _codePreviewFrame.srcdoc = buildPreviewSrcdoc(lang, code);
  _codePreviewModal.classList.add('visible');
}

/** 关闭代码预览弹层。 */
function closeCodePreview() {
  if (!_codePreviewModal || !_codePreviewFrame) return;
  _codePreviewModal.classList.remove('visible');
  _codePreviewFrame.srcdoc = '';
}

/** 重新加载当前预览文档。 */
function reloadCodePreview() {
  if (!_codePreviewFrame) return;
  _codePreviewFrame.srcdoc = buildPreviewSrcdoc(
    _codePreviewState.lang,
    _codePreviewState.code,
  );
}

/** 代码块预览入口：仅支持白名单语言。 */
function previewCode(btn) {
  const payload = getCodeBlockPayload(btn);
  if (!payload || !canPreviewCodeLanguage(payload.lang)) return;
  openCodePreview(payload.lang, payload.code);
}

/**
 * 复制文本到剪贴板：
 * 1) 优先使用 Clipboard API
 * 2) 在不满足安全上下文或权限时回退到 execCommand
 */
function copyTextToClipboard(text) {
  if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
    return navigator.clipboard.writeText(text).catch(() => fallbackCopyText(text));
  }
  return fallbackCopyText(text);
}

function fallbackCopyText(text) {
  return new Promise((resolve, reject) => {
    try {
      const input = document.createElement('textarea');
      input.value = text;
      input.setAttribute('readonly', '');
      input.style.position = 'fixed';
      input.style.top = '-9999px';
      input.style.opacity = '0';
      document.body.appendChild(input);
      input.focus();
      input.select();
      input.setSelectionRange(0, input.value.length);
      const ok = document.execCommand('copy');
      document.body.removeChild(input);
      if (ok) {
        resolve();
      } else {
        reject(new Error('execCommand copy failed'));
      }
    } catch (e) {
      reject(e);
    }
  });
}

// ===== Long press detection =====
let _longPressTimer = null;

function startLongPress(event, id) {
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

function handleContextMenu(event, id) {
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
    caps.push('<span class="ms-icon model-cap" title="支持视觉">visibility</span>');
  }
  if (supportsTools) {
    caps.push('<span class="ms-icon model-cap" title="支持工具">build</span>');
  }
  return caps.join('');
}

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
    updateAssistantContentDOM(msg);
    if (isNearBottom()) scrollToBottom(false);
  },

  /** 更新思考内容（流式追加） */
  updateThinkingContent(id, content, timeMs) {
    const msg = state.messages.find((m) => m.id === id);
    if (!msg) return;
    msg.reasoning = content;
    if (timeMs !== undefined) msg.reasoningTimeMs = timeMs;
    updateReasoningDOM(msg);
    if (isNearBottom()) scrollToBottom(false);
  },

  /** 标记消息流式结束 */
  endStreaming(id, canContinue) {
    const msg = state.messages.find((m) => m.id === id);
    if (!msg) return;
    msg.isStreaming = false;
    msg.canContinue = !!canContinue;
    delete state.streamingMarkdownSnapshots[id];
    updateMessageDOM(msg);
  },

  /** 删除消息 */
  deleteMessage(id) {
    const idx = state.messages.findIndex((m) => m.id === id);
    if (idx === -1) return;
    state.messages.splice(idx, 1);
    delete state.streamingMarkdownSnapshots[id];
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
    state.streamingMarkdownSnapshots = {};
    renderAllMessages();
  },

  /** 批量加载消息（初始加载或历史分页） */
  loadMessages(jsonStr, prepend) {
    const msgs = JSON.parse(jsonStr);
    if (prepend) {
      state.messages = msgs.concat(state.messages);
      // 历史消息只前插新增片段，避免已加载 Markdown/图片全部重绘。
      prependMessagesDOM(msgs);
    } else {
      state.messages = msgs;
      state.streamingMarkdownSnapshots = {};
      renderAllMessages();
      scrollToBottom(false);
    }
  },

  /** 设置生成状态 */
  setGeneratingState(isGenerating) {
    const normalized = !!isGenerating;
    const changed = state.isGenerating !== normalized;
    state.isGenerating = normalized;
    updateSendButton();
    // “继续”按钮在渲染期按生成态控制显隐，状态变化时需重绘才能正确恢复。
    if (changed) {
      renderAllMessages();
    } else {
      refreshMessageActionButtonsState();
    }
    if (normalized) {
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
