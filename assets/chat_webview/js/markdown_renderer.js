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
