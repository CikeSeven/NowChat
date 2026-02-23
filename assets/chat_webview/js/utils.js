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
