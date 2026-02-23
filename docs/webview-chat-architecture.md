# WebView 聊天面板技术架构文档

## 概述

聊天界面使用 Flutter `WebViewWidget` 承载一个完整的 HTML/CSS/JS 前端来渲染消息列表和输入区域。Flutter 侧负责业务逻辑（消息收发、会话管理、文件选取等），WebView 侧负责 UI 渲染（Markdown、代码高亮、LaTeX 公式等）。两者通过 JSON 协议双向通信。

## 技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| Flutter 宿主 | `webview_flutter` | 嵌入 WebView 并注册 JS Channel |
| Flutter 宿主 | `dart:io` HttpServer | 本地图片代理服务器，让 WebView 能访问设备文件 |
| JS 渲染 | [marked.js](https://github.com/markedjs/marked) v14.1.4 | Markdown → HTML |
| JS 渲染 | [highlight.js](https://highlightjs.org/) v11.9.0 | 代码语法高亮（GitHub 主题） |
| JS 渲染 | [KaTeX](https://katex.org/) v0.16.11 | LaTeX 数学公式渲染 |
| 图标 | [Material Symbols Rounded](https://fonts.google.com/icons) | Google Fonts CDN 加载，通过 `icon(name)` 辅助函数生成 `<span class="ms-icon">` |
| 样式 | CSS Custom Properties | 运行时由 Flutter 注入 Material 主题色 |

## 文件清单

```
assets/chat_webview/
├── index.html          # HTML 骨架 + CDN 依赖引入
├── bridge.js           # JS → Flutter 通信桥（Bridge 对象）
├── chat.js             # 消息渲染引擎 + Flutter → JS API（ChatBridge 对象）
└── style.css           # 全部样式，CSS 变量主题化

lib/ui/widgets/
└── chat_webview_panel.dart   # WebView 宿主 Widget + 本地图片代理服务器

lib/ui/pages/
└── chat_detail_page.dart     # 聊天页面，组装 ChatWebViewPanel 并实现所有回调
```

## 通信架构

```
┌─────────────────────────────────────────────────────┐
│  Flutter (ChatDetailPage + ChatWebViewPanel)         │
│                                                     │
│  ┌─ ChatProvider ──────────────────────────────┐    │
│  │  消息列表、会话状态、AI 生成控制             │    │
│  └─────────────────────────────────────────────┘    │
│         │                          ▲                │
│    didUpdateWidget              回调触发            │
│    _evalJs("ChatBridge.xxx()")  _handleJsMessage()  │
│         │                          │                │
│  ═══════╪══════════════════════════╪════════════     │
│         ▼                          │                │
│  ┌─ WebView ───────────────────────────────────┐    │
│  │  window.ChatBridge.xxx()    Bridge.xxx()    │    │
│  │  (Flutter→JS)               (JS→Flutter)    │    │
│  │                                             │    │
│  │  chat.js 渲染引擎                            │    │
│  │  marked.js + highlight.js + KaTeX           │    │
│  └─────────────────────────────────────────────┘    │
│                                                     │
│  ┌─ _LocalImageServer (127.0.0.1:随机端口) ────┐    │
│  │  GET /local-image?path=<本地路径>            │    │
│  │  WebView 通过 HTTP 请求获取本地图片          │    │
│  └─────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

## Flutter → JS 接口（ChatBridge）

Flutter 通过 `_evalJs("ChatBridge.xxx()")` 调用，定义在 `chat.js` 的 `window.ChatBridge` 对象中。

| 方法 | 参数 | 用途 |
|------|------|------|
| `addMessage(jsonStr)` | 单条消息 JSON 字符串 | 追加一条新消息 |
| `updateMessageContent(id, content)` | 消息 ID, 新内容 | 流式更新消息正文 |
| `updateThinkingContent(id, content, timeMs)` | 消息 ID, 思考内容, 耗时 ms | 流式更新思考/推理块 |
| `endStreaming(id, canContinue)` | 消息 ID, 是否可继续 | 标记流式结束，显示操作按钮 |
| `deleteMessage(id)` | 消息 ID | 删除单条消息 |
| `clearMessages()` | 无 | 清空所有消息（切换会话时） |
| `loadMessages(jsonStr, prepend)` | 消息数组 JSON, 是否前插 | 批量加载（初始/历史分页） |
| `setGeneratingState(isGenerating)` | bool | 切换生成状态（发送按钮↔停止按钮） |
| `setSystemPrompt(text)` | 字符串 | 设置系统提示词并重新渲染卡片 |
| `addToolLog(messageId, logJson)` | 消息 ID, 日志 JSON | 追加工具执行日志 |
| `setAttachments(jsonStr)` | 路径数组 JSON | 更新输入区附件预览 |
| `setTheme(jsonStr)` | CSS 变量名→颜色值 JSON | 注入 Material 主题色 |
| `setModelInfo(name, supportsVision, supportsTools)` | 名称, bool, bool | 更新模型显示和功能标记 |
| `setStreamingState(isStreaming, supported)` | bool, bool | 同步流式开关状态 |
| `setLoadingMore(loading)` | bool | 设置"加载更多"状态 |
| `setImageProxyBase(base)` | URL 字符串 | 设置本地图片代理地址 |
| `scrollToBottom(animated)` | bool | 滚动到底部 |

## JS → Flutter 接口（Bridge）

JS 通过 `Bridge.xxx()` 调用，定义在 `bridge.js`。Flutter 侧在 `_handleJsMessage()` 中按 `action` 字段分发。

| 方法 | 传递字段 | 用途 |
|------|---------|------|
| `onReady()` | — | WebView 加载完成，触发全量状态同步 |
| `onSendMessage(text)` | `text` | 用户发送消息 |
| `onStopGenerating()` | — | 用户打断生成 |
| `onPickImage()` | — | 选择图片 |
| `onPickFile()` | — | 选择文件 |
| `onRemoveAttachment(path)` | `path` | 移除待发送附件 |
| `onLinkTap(url)` | `url` | 点击链接 |
| `onImageTap(url)` | `url` | 点击图片 |
| `onScrollNearTop()` | — | 滚动接近顶部，加载历史 |
| `onToggleStreaming(value)` | `value: bool` | 切换流式开关 |
| `onSelectModel()` | — | 点击模型选择器 |
| `onMessageAction(id, action)` | `id, msgAction` | 消息操作（见下表） |
| `onShowAttachmentMenu()` | — | 点击"+"按钮弹出附件菜单 |
| `onUserMessageLongPress(id)` | `id` | 长按用户消息 |

### onMessageAction 的 action 值

| action 值 | 触发场景 | Flutter 侧行为 |
|-----------|---------|----------------|
| `resend` | AI 消息底部重发按钮 | `chatProvider.regenerateMessage()` |
| `continue` | AI 消息底部继续按钮 | `chatProvider.continueGeneratingAssistantMessage()` |
| `edit` | AI 消息底部编辑按钮 | 跳转编辑消息页面 |
| `copy` | AI 消息底部复制按钮 | 复制到剪贴板 |
| `more` | AI 消息底部更多按钮（三个点） | 弹出 BottomSheet 菜单 |
| `delete` | 菜单中删除 | `chatProvider.deleteMessage()` |
| `editSystemPrompt` | 点击 System Prompt 卡片 | 弹出系统提示词编辑对话框 |

## 消息 JSON 结构

Flutter `_messageToJson()` 生成，JS 侧消费：

```json
{
  "id": 123,
  "role": "user | assistant",
  "content": "消息正文",
  "reasoning": "思考过程文本",
  "reasoningTimeMs": 3200,
  "imagePaths": ["http://127.0.0.1:PORT/local-image?path=..."],
  "isStreaming": false,
  "isLast": true,
  "canContinue": false,
  "toolLogs": [
    { "toolName": "python", "summary": "执行成功", "status": "success" }
  ]
}
```

## 本地图片代理服务器

**文件**: `chat_webview_panel.dart` 中的 `_LocalImageServer` 单例类。

**原因**: WebView 无法直接访问 `file:///` 本地文件路径。

**机制**:
1. `initState()` 时启动 HTTP 服务器，绑定 `127.0.0.1` 随机端口
2. `_syncFullState()` 时将 `http://127.0.0.1:<port>` 传给 JS 侧 `ChatBridge.setImageProxyBase()`
3. `_messageToJson()` 将 `imagePaths` 中的本地路径转为代理 URL
4. JS 侧 `proxyImageUrl()` 将 Markdown 中的本地图片路径也转为代理 URL
5. WebView 发起 HTTP 请求 → 服务器读取本地文件 → 返回图片字节流

## 增量同步机制

**文件**: `chat_webview_panel.dart` 的 `_syncMessages()` 方法。

为避免每次 `didUpdateWidget` 全量重绘，使用增量对比：

| 检测项 | 对比方式 | JS 调用 |
|--------|---------|---------|
| 历史消息前插 | 新 ID 列表头部多出的部分 | `loadMessages(json, true)` |
| 新消息追加 | ID 不在 `_syncedMessageIds` 中 | `addMessage(json)` |
| 消息删除 | 旧 ID 不在新列表中 | `deleteMessage(id)` |
| 内容更新（流式） | `content.length` 变化 | `updateMessageContent(id, content)` |
| 思考更新（流式） | `reasoning.length` 变化 | `updateThinkingContent(id, content, timeMs)` |
| 工具日志新增 | `toolLogs.length` 增长 | `addToolLog(messageId, logJson)` |
| 流式结束 | `isMessageStreaming` 返回 false | `endStreaming(id, canContinue)` |

## 主题同步

Flutter 的 `ColorScheme` 在 `_syncTheme()` 中转为 CSS 变量名→十六进制颜色值的 Map，通过 `ChatBridge.setTheme()` 注入。CSS 中所有颜色均使用 `var(--xxx)` 引用，实现动态主题切换。

## 维护注意事项

### Bridge 字段命名冲突

`bridge.js` 的 `_post(action, data)` 使用 `{ action, ...data }` 展开。如果 `data` 中也有 `action` 字段，会覆盖外层的 `action`。因此 `onMessageAction` 使用 `msgAction` 作为数据字段名。**新增 Bridge 方法时避免在 data 中使用 `action` 作为 key。**

### 流式更新与 DOM 状态保持

`updateMessageDOM()` 会替换整个消息 DOM 节点。当前已实现保存/恢复 reasoning 展开状态。**如果未来新增其他可交互的折叠/展开组件，需要在 `updateMessageDOM()` 中同样保存和恢复其状态。**

### HTML 内联加载

`_loadHtmlFromAssets()` 将 CSS 和 JS 内联到 HTML 中，通过字符串替换 `<link>` 和 `<script>` 标签。**修改 `index.html` 中这些标签的格式时，需确保替换字符串完全匹配。**

### 图片代理服务器生命周期

`_LocalImageServer` 是进程级单例，不随 Widget 销毁。**如果应用需要在后台释放端口资源，需要额外实现 `stop()` 方法并在合适时机调用。**

### JS 字符串转义

`_escJs()` 方法转义 `\`、`'`、`\n`、`\r`、`\t`。**如果消息内容包含其他特殊字符（如 `\0`），可能需要扩展转义规则。**

### CDN 依赖

marked.js、highlight.js、KaTeX 从 CDN 加载。**离线场景需要将这些库打包到本地 assets 中，并修改 `index.html` 的引用路径。**

### 新增消息操作按钮

1. 在 `chat.js` 的 `renderAssistantMessage()` 中添加按钮 HTML
2. 按钮 `onclick` 调用 `Bridge.onMessageAction(id, 'newAction')`
3. 在 `chat_detail_page.dart` 的 `_handleMessageAction()` switch 中添加对应 case

### Material Symbols 图标

所有图标使用 Google Material Symbols Rounded 字体，通过 `chat.js` 中的 `icon(name)` 辅助函数生成：

```js
function icon(name, extraClass = '') {
  const cls = extraClass ? `ms-icon ${extraClass}` : 'ms-icon';
  return `<span class="${cls}" aria-hidden="true">${name}</span>`;
}
```

图标名称直接使用 [Material Symbols](https://fonts.google.com/icons) 的 ligature 名称，如 `refresh`、`edit`、`content_copy`、`more_horiz`、`send`、`stop_circle`、`add`、`tune`、`play_arrow` 等。**新增图标时只需传入正确的 ligature 名称即可，无需额外导入 SVG。**
