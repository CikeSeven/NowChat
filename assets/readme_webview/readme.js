/**
 * readme.js - 插件 README WebView 渲染引擎
 *
 * 设计目标：
 * 1. Markdown 渲染风格与聊天页 assistant 正文保持一致。
 * 2. 仅做只读预览，不包含聊天输入区与消息操作按钮。
 * 3. 使用 Shadow DOM 隔离 README 内样式，避免污染页面其它元素。
 */

const state = {
  content: '',
  localReadmeDir: '',
  repoRawBase: '',
  imageProxyBase: '',
};

let $list;

document.addEventListener('DOMContentLoaded', () => {
  $list = document.getElementById('message-list');
  setupMarked();
  Bridge.onReady();
});

const README_SHADOW_STYLE = `
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

.code-block-header .copy-btn {
  background: none;
  border: none;
  color: var(--on-surface-variant);
  cursor: pointer;
  width: 34px;
  height: 34px;
  padding: 0;
  border-radius: 8px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

.code-block-header .copy-btn .ms-icon {
  font-size: 28px;
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

function setupMarked() {
  const renderer = new marked.Renderer();

  renderer.code = function(code, lang) {
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
        <button class="copy-btn" onclick="copyCode(this)" title="复制代码">${icon('content_copy')}</button>
      </div>
      <pre><code class="hljs language-${escHtml(language)}">${highlighted}</code></pre>
    </div>`;
  };

  renderer.image = function(href, title, text) {
    if (typeof href === 'object') { title = href.title; text = href.text; href = href.href; }
    const resolved = resolveReadmeUrl((href || '').trim(), true);
    return `<img src="${escHtml(resolved)}" alt="${escHtml(text || '')}" title="${escHtml(title || '')}" onclick="Bridge.onImageTap('${escJs(resolved)}')" />`;
  };

  renderer.link = function(href, title, text) {
    if (typeof href === 'object') { title = href.title; text = href.text; href = href.href; }
    const resolved = resolveReadmeUrl((href || '').trim(), false);
    return `<a href="javascript:void(0)" onclick="Bridge.onLinkTap('${escJs(resolved)}')" title="${escHtml(title || '')}">${text}</a>`;
  };

  marked.setOptions({
    renderer,
    gfm: true,
    breaks: true,
  });
}

function renderMarkdown(text) {
  if (!text) return '';
  const blocks = [];
  text = text.replace(/\$\$([\s\S]+?)\$\$/g, (_, tex) => {
    const idx = blocks.length;
    blocks.push({ tex, display: true });
    return `%%LATEX_BLOCK_${idx}%%`;
  });
  text = text.replace(/(?<!\$)\$(?!\$)(.+?)(?<!\$)\$(?!\$)/g, (_, tex) => {
    const idx = blocks.length;
    blocks.push({ tex, display: false });
    return `%%LATEX_INLINE_${idx}%%`;
  });

  let html = marked.parse(text);
  html = html.replace(/%%LATEX_BLOCK_(\d+)%%/g, (_, i) => {
    const b = blocks[parseInt(i, 10)];
    try {
      return katex.renderToString(b.tex, { displayMode: true, throwOnError: false });
    } catch (_) {
      return `<code>${escHtml(b.tex)}</code>`;
    }
  });
  html = html.replace(/%%LATEX_INLINE_(\d+)%%/g, (_, i) => {
    const b = blocks[parseInt(i, 10)];
    try {
      return katex.renderToString(b.tex, { displayMode: false, throwOnError: false });
    } catch (_) {
      return `<code>${escHtml(b.tex)}</code>`;
    }
  });
  return html;
}

function renderReadme() {
  if (!$list) return;
  const markdown = (state.content || '').trim();
  if (!markdown) {
    $list.innerHTML = '<div class="empty-state"><span>暂无 README 内容</span></div>';
    return;
  }

  $list.innerHTML = '<div class="msg msg-assistant"><div class="msg-content-host" id="readme-host"></div></div>';
  const host = document.getElementById('readme-host');
  if (!host) return;

  if (!host.shadowRoot) {
    host.attachShadow({ mode: 'open' });
  }
  host.shadowRoot.innerHTML =
    `<style>${README_SHADOW_STYLE}</style><div class="md-root">${renderMarkdown(markdown)}</div>`;

  wireRawHtmlInteractions(host.shadowRoot);
}

/**
 * 为 Markdown 中的原始 HTML（非 marked renderer 生成）补充链接/图片行为：
 * - 统一解析相对 URL
 * - 拦截点击并回传 Flutter
 */
function wireRawHtmlInteractions(shadowRoot) {
  if (!shadowRoot) return;
  const images = shadowRoot.querySelectorAll('img');
  for (const img of images) {
    const raw = (img.getAttribute('src') || '').trim();
    if (!raw) continue;
    const resolved = resolveReadmeUrl(raw, true);
    img.setAttribute('src', resolved);
    img.onclick = () => Bridge.onImageTap(resolved);
  }

  const links = shadowRoot.querySelectorAll('a');
  for (const anchor of links) {
    const raw = (anchor.getAttribute('href') || '').trim();
    if (!raw || raw.toLowerCase().startsWith('javascript:')) continue;
    const resolved = resolveReadmeUrl(raw, false);
    anchor.setAttribute('href', 'javascript:void(0)');
    anchor.onclick = () => Bridge.onLinkTap(resolved);
  }
}

window.ReadmeBridge = {
  setTheme(jsonStr) {
    const colors = JSON.parse(jsonStr);
    const root = document.documentElement;
    for (const [key, value] of Object.entries(colors)) {
      root.style.setProperty(`--${key}`, value);
    }
  },
  setContext(localReadmeDir, repoRawBase, imageProxyBase) {
    state.localReadmeDir = (localReadmeDir || '').trim();
    state.repoRawBase = (repoRawBase || '').trim();
    state.imageProxyBase = (imageProxyBase || '').trim();
  },
  setReadme(content) {
    state.content = content || '';
    renderReadme();
  },
};

function resolveReadmeUrl(raw, forImage) {
  const input = (raw || '').trim();
  if (!input) return '';

  // hash 锚点原样保留。
  if (input.startsWith('#')) return input;

  // 已是完整 URI。
  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(input)) {
    return forImage ? proxyImageUrl(input) : input;
  }

  // 协议相对 URL。
  if (input.startsWith('//')) {
    const absolute = `https:${input}`;
    return forImage ? proxyImageUrl(absolute) : absolute;
  }

  // 绝对路径：优先本地路径；远端 README 场景回落到仓库根相对路径。
  if (input.startsWith('/')) {
    if (state.localReadmeDir) {
      const localAbsolute = normalizeLocalPath(input);
      return forImage ? proxyImageUrl(localAbsolute) : localAbsolute;
    }
    if (state.repoRawBase) {
      const relative = input.replace(/^\/+/, '');
      return safeUrlJoin(state.repoRawBase, relative) || input;
    }
    return forImage ? proxyImageUrl(input) : input;
  }

  // 相对路径：本地 README 先按本地目录解析。
  if (state.localReadmeDir) {
    const localPath = normalizeLocalPath(`${state.localReadmeDir}/${input}`);
    return forImage ? proxyImageUrl(localPath) : localPath;
  }

  // 远端 README 再按仓库 raw 基址解析。
  if (state.repoRawBase) {
    const remoteUrl = safeUrlJoin(state.repoRawBase, input);
    if (remoteUrl) {
      return forImage ? proxyImageUrl(remoteUrl) : remoteUrl;
    }
  }

  return input;
}

function safeUrlJoin(base, relative) {
  try {
    return new URL(relative, base).toString();
  } catch (_) {
    return null;
  }
}

function normalizeLocalPath(path) {
  const input = (path || '').replace(/\\/g, '/');
  const driveMatch = input.match(/^([a-zA-Z]:)(\/|$)/);
  const hasRoot = input.startsWith('/');
  const segments = input.split('/');
  const out = [];
  for (const segment of segments) {
    if (!segment || segment === '.') continue;
    if (segment === '..') {
      if (out.length > 0 && out[out.length - 1] !== '..') {
        out.pop();
      }
      continue;
    }
    out.push(segment);
  }

  if (driveMatch) {
    const drive = driveMatch[1];
    if (out.length > 0 && out[0].toLowerCase() === drive.toLowerCase()) {
      out.shift();
    }
    return `${drive}/${out.join('/')}`;
  }
  return `${hasRoot ? '/' : ''}${out.join('/')}`;
}

function proxyImageUrl(path) {
  const input = (path || '').trim();
  if (!input) return input;
  if (/^(https?:|data:)/i.test(input)) return input;
  if (!isImagePath(input)) return input;
  if (!state.imageProxyBase) return input;
  if (!isLocalAbsolutePath(input)) return input;
  return `${state.imageProxyBase}/local-image?path=${encodeURIComponent(input)}`;
}

function isImagePath(path) {
  const value = (path || '').toLowerCase();
  const pure = value.split('?')[0].split('#')[0];
  return /\.(png|jpg|jpeg|webp|gif|bmp|heic|heif|svg)$/.test(pure);
}

function isLocalAbsolutePath(path) {
  const value = (path || '').trim();
  if (value.startsWith('file://')) return true;
  if (/^[a-zA-Z]:[\\/]/.test(value)) return true;
  return value.startsWith('/data/') || value.startsWith('/storage/') || value.startsWith('/sdcard/') || value.startsWith('/');
}

function copyCode(btn) {
  const pre = btn.closest('.code-block-wrapper')?.querySelector('pre code');
  if (!pre) return;
  copyTextToClipboard(pre.textContent || '').then(() => {
    btn.innerHTML = icon('check');
    setTimeout(() => { btn.innerHTML = icon('content_copy'); }, 1200);
  }).catch(() => {
    btn.innerHTML = icon('content_copy');
  });
}

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

function icon(name, extraClass = '') {
  const cls = extraClass ? `ms-icon ${extraClass}` : 'ms-icon';
  return `<span class="${cls}" aria-hidden="true">${name}</span>`;
}
