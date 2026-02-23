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
