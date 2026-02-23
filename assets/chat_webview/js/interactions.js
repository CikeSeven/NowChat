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
