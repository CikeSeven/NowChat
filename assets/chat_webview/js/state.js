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
