# WebView 聊天面板技术架构文档

## 概述

聊天界面采用 Flutter `WebViewWidget` 承载一套 HTML/CSS/JS 前端。

- Flutter 负责业务与状态: 会话、消息、流式生成、附件、Provider/Model 配置、历史分页。
- WebView 负责渲染与交互: 消息列表、Markdown/LaTeX/高亮、输入区、消息操作按钮、代码块工具。
- 双向通信通过 JSON 协议完成:
  - Flutter -> JS: `window.ChatBridge`
  - JS -> Flutter: `window.Bridge` + `FlutterBridge` JavaScriptChannel

当前方案核心目标:

1. 让聊天 UI 渲染不受 Flutter Widget 复杂层级限制。
2. 让 Markdown/HTML/代码块能力可持续扩展。
3. 保持 Flutter 业务侧的可维护性与可观测性。

## 技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| Flutter 宿主 | `webview_flutter` | 嵌入 WebView 并注册 JS Channel |
| Flutter 宿主 | `dart:io` `HttpServer` | 本地图片代理服务器，让 WebView 能访问设备文件 |
| JS 渲染 | [marked.js](https://github.com/markedjs/marked) v14.1.4 | Markdown -> HTML |
| JS 渲染 | [highlight.js](https://highlightjs.org/) v11.9.0 | 代码语法高亮（GitHub 主题） |
| JS 渲染 | [KaTeX](https://katex.org/) v0.16.11 | LaTeX 数学公式渲染 |
| 图标 | [Material Symbols Rounded](https://fonts.google.com/icons) | 通过 `icon(name)` 生成 ligature 图标 |
| 样式 | CSS Custom Properties | 运行时由 Flutter 注入 Material 主题色 |

## 文件清单

### 运行时资产（Flutter 实际加载）

```text
assets/chat_webview/
├── index.html          # HTML 骨架 + CDN 依赖 + DOM 容器
├── bridge.js           # JS -> Flutter 通信桥（Bridge）
├── chat.js             # JS 运行时 bundle（渲染/交互/ChatBridge API）
└── style.css           # CSS 运行时 bundle（全局样式）
```

### 源码模块（按职责拆分，便于维护）

```text
assets/chat_webview/
├── js/
│   ├── state.js            # 全局状态与 DOM 引用
│   ├── utils.js            # 通用工具（转义、图标、路径、图片代理）
│   ├── markdown_renderer.js# Markdown/KaTeX/代码块渲染 + Shadow DOM
│   ├── message_renderer.js # 消息 HTML 生成与增量节点更新
│   ├── interactions.js     # 输入/滚动/复制/长按/代码预览交互
│   └── bridge_api.js       # Flutter -> JS 的 ChatBridge API
└── css/
    ├── base.css            # reset、变量、基础布局
    ├── messages.css        # 消息区样式
    ├── markdown.css        # Markdown 与代码块样式
    ├── input.css           # 输入区样式
    └── effects.css         # 动效（ripple/spinner/FAB）
```

### Flutter 宿主代码

```text
lib/ui/widgets/chat_webview_panel.dart   # WebView 宿主、Bridge 分发、增量同步、本地图片代理
lib/ui/pages/chat_detail_page.dart       # 聊天页面，组装 ChatWebViewPanel 与业务回调
```

## 文件结构特点与特性

### 1) 双轨结构（模块源码 + 运行时 bundle）

- `js/*`、`css/*` 是“按功能拆分”的维护入口。
- `chat.js`、`style.css` 是“运行时加载入口”。
- `ChatWebViewPanel._loadHtmlFromAssets()` 会将 `index.html + bridge.js + chat.js + style.css` 内联为单页字符串后加载，避免相对路径失效。

特性:

- 本地调试时可直接查看 bundle 行为。
- 模块化源码更利于多人维护、功能扩展与回归排查。

### 2) 渲染与业务完全分层

- Flutter 不负责逐条绘制消息 UI，只负责把状态“推送给 WebView”。
- WebView 不直接参与会话业务，只负责渲染和用户交互事件上报。

特性:

- 业务逻辑集中在 Provider 层，便于测试。
- UI 迭代速度快，不需要频繁改 Flutter Widget 树。

### 3) 状态驱动 + 增量同步

- Flutter 侧维护 `_syncedMessageIds`、`_syncedContentLengths`、`_syncedReasoningLengths`、`_syncedToolLogCounts`。
- `didUpdateWidget()` 中按差异调用 `ChatBridge`，尽量避免全量重绘。

特性:

- 流式输出时更新粒度小，减少重排与卡顿。
- 历史分页采用 prepend 模式，保留用户滚动位置。

### 4) 样式隔离与渲染安全

- Assistant 正文渲染在 Shadow DOM（`msg-content-host`）内，防止消息中的样式污染消息操作按钮或输入区。
- 代码预览使用 `iframe srcdoc` + `sandbox="allow-scripts allow-forms"`，将可执行内容限制在预览容器内。

特性:

- 降低 AI 生成 HTML/CSS 破坏全局布局的概率。
- 保持消息区工具按钮与输入区 UI 稳定。

### 5) 本地图片可见性保障

- Flutter 本地 `HttpServer` 暴露 `/local-image?path=...`。
- Flutter 与 JS 双侧都会重写本地图片路径为 `127.0.0.1` 代理 URL。
- 仅图片扩展名允许走代理，避免普通文件误当图片渲染。

特性:

- 支持 Markdown/HTML 中引用 Android 本地路径图片。
- 避免 WebView 直接访问 `file://` 导致加载失败。

### 6) 可扩展的代码预览机制

- 预览能力由 `CodePreviewRegistry` 管理，不通过 `if/else` 硬编码语言分支。
- 对外暴露:
  - `window.CodePreviewRegistry.register(language, renderer, aliases)`
  - `window.CodePreviewRegistry.unregister(language)`
  - `window.CodePreviewRegistry.list()`
- 当前默认内置 `html/htm` 预览渲染器（通过注册表注入）。

特性:

- 后续支持 `svg`、`mermaid`、`markdown` 等语言时，只需注册渲染器，无需修改核心判断逻辑。

## 通信架构

```text
┌──────────────────────────────────────────────────────┐
│ Flutter (ChatDetailPage + ChatWebViewPanel)         │
│                                                      │
│  ┌─ ChatProvider ─────────────────────────────────┐  │
│  │ 消息列表、会话状态、AI 生成控制                 │  │
│  └────────────────────────────────────────────────┘  │
│        │                          ▲                  │
│   didUpdateWidget()           回调触发               │
│   _evalJs("ChatBridge.xxx")   _handleJsMessage()     │
│        │                          │                  │
│  ══════╪══════════════════════════╪══════════════    │
│        ▼                          │                  │
│  ┌─ WebView ─────────────────────────────────────┐   │
│  │ window.ChatBridge.xxx()   Bridge.xxx()        │   │
│  │ (Flutter -> JS)           (JS -> Flutter)     │   │
│  │                                                │   │
│  │ chat.js 渲染引擎 + 模块化能力                 │   │
│  │ marked.js + highlight.js + KaTeX              │   │
│  └────────────────────────────────────────────────┘   │
│                                                      │
│  ┌─ _LocalImageServer (127.0.0.1:随机端口) ──────┐   │
│  │ GET /local-image?path=<本地路径>               │   │
│  │ WebView 通过 HTTP 请求获取本地图片             │   │
│  └────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────┘
```

## Flutter -> JS 接口（ChatBridge）

Flutter 通过 `_evalJs("ChatBridge.xxx()")` 调用，定义在 `chat.js` 的 `window.ChatBridge` 中。

| 方法 | 参数 | 用途 |
|------|------|------|
| `addMessage(jsonStr)` | 单条消息 JSON 字符串 | 追加一条新消息 |
| `updateMessageContent(id, content)` | 消息 ID, 新内容 | 流式更新正文 |
| `updateThinkingContent(id, content, timeMs)` | 消息 ID, 思考内容, 耗时 ms | 流式更新思考块 |
| `endStreaming(id, canContinue)` | 消息 ID, 是否可继续 | 标记流式结束，恢复操作区 |
| `deleteMessage(id)` | 消息 ID | 删除单条消息 |
| `clearMessages()` | 无 | 清空所有消息 |
| `loadMessages(jsonStr, prepend)` | 消息数组 JSON, 是否前插 | 初始加载/历史分页 |
| `setGeneratingState(isGenerating)` | bool | 同步生成状态并触发必要重绘 |
| `setSystemPrompt(text)` | 字符串 | 设置系统提示词 |
| `addToolLog(messageId, logJson)` | 消息 ID, 日志 JSON | 追加工具日志 |
| `setAttachments(jsonStr)` | 路径数组 JSON | 更新输入区附件预览 |
| `setTheme(jsonStr)` | CSS 变量名 -> 颜色值 JSON | 注入 Material 主题色 |
| `setModelInfo(name, supportsVision, supportsTools)` | 名称, bool, bool | 更新模型显示与能力图标 |
| `setStreamingState(isStreaming, supported)` | bool, bool | 同步流式开关 |
| `setLoadingMore(loading)` | bool | 设置历史加载状态 |
| `setImageProxyBase(base)` | URL 字符串 | 设置本地图片代理地址 |
| `scrollToBottom(animated)` | bool | 滚动到底部 |

## JS -> Flutter 接口（Bridge）

JS 通过 `Bridge.xxx()` 调用，定义在 `bridge.js`。Flutter 侧在 `_handleJsMessage()` 按 `action` 分发。

| 方法 | 传递字段 | 用途 |
|------|---------|------|
| `onReady()` | - | WebView 就绪，触发全量同步 |
| `onSendMessage(text)` | `text` | 发送消息 |
| `onStopGenerating()` | - | 打断生成 |
| `onPickImage()` | - | 选择图片 |
| `onPickFile()` | - | 选择文件 |
| `onRemoveAttachment(path)` | `path` | 移除待发送附件 |
| `onLinkTap(url)` | `url` | 点击链接 |
| `onImageTap(url)` | `url` | 点击图片 |
| `onScrollNearTop()` | - | 接近顶部触发历史加载 |
| `onToggleStreaming(value)` | `value` | 切换流式开关 |
| `onSelectModel()` | - | 打开模型选择 |
| `onMessageAction(id, action)` | `id`, `msgAction` | 消息操作 |
| `onShowAttachmentMenu()` | - | 打开附件菜单 |
| `onUserMessageLongPress(id)` | `id` | 用户消息长按 |

### onMessageAction 的 action 值

| action 值 | 场景 | Flutter 侧行为 |
|-----------|------|----------------|
| `resend` | AI 消息重发按钮 | `chatProvider.regenerateMessage()` |
| `continue` | AI 消息继续按钮 | `chatProvider.continueGeneratingAssistantMessage()` |
| `edit` | AI 消息编辑按钮 | 跳转编辑页 |
| `copy` | AI 消息复制按钮 | 复制到剪贴板 |
| `more` | AI 消息更多按钮 | 弹出 BottomSheet 菜单 |
| `delete` | 菜单删除 | `chatProvider.deleteMessage()` |
| `editSystemPrompt` | 点击 System Prompt 卡片 | 弹出系统提示词编辑框 |

## 消息 JSON 结构

Flutter `_messageToJson()` 生成，JS 侧消费:

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

**文件**: `lib/ui/widgets/chat_webview_panel.dart` 中 `_LocalImageServer`。

**原因**: WebView 无法稳定直接读取 `file://` 设备文件。

**机制**:

1. `initState()` 启动 `HttpServer`，绑定 `127.0.0.1` 随机端口
2. `_syncFullState()` 将代理地址通过 `ChatBridge.setImageProxyBase()` 发给 JS
3. Flutter `_messageToJson()` 重写附件路径
4. JS `proxyImageUrl()` 重写 Markdown/HTML 中本地图片路径
5. WebView 请求 `/local-image`，Flutter 读取文件并回传字节流

## 增量同步机制

**文件**: `lib/ui/widgets/chat_webview_panel.dart` 的 `_syncMessages()`。

| 检测项 | 对比方式 | JS 调用 |
|--------|---------|---------|
| 历史消息前插 | 新 ID 头部增量 | `loadMessages(json, true)` |
| 新消息追加 | ID 不在 `_syncedMessageIds` | `addMessage(json)` |
| 消息删除 | 旧 ID 不在新列表 | `deleteMessage(id)` |
| 内容更新（流式） | `content.length` 变化 | `updateMessageContent(id, content)` |
| 思考更新（流式） | `reasoning.length` 变化 | `updateThinkingContent(id, content, timeMs)` |
| 工具日志新增 | `toolLogs.length` 增长 | `addToolLog(messageId, logJson)` |
| 流式结束 | `isMessageStreaming=false` | `endStreaming(id, canContinue)` |

## 主题同步

Flutter `ColorScheme` 在 `_syncTheme()` 中转为 CSS 变量 Map，通过 `ChatBridge.setTheme()` 注入。WebView 侧颜色使用 `var(--xxx)`，支持运行时主题切换。

## 维护注意事项

### 1) Bundle 与模块源码同步

运行时读取 `chat.js/style.css`，而非 `js/*`、`css/*`。修改模块源码后，必须确保 bundle 同步到一致版本，否则会出现“代码改了但界面无变化”。

### 2) Bridge 字段命名冲突

`bridge.js` 的 `_post(action, data)` 使用 `{ action, ...data }`。`data` 内如果也有 `action` key 会覆盖外层动作名，所以消息动作字段使用 `msgAction`。新增 Bridge 方法时不要复用 `action` 作为 data key。

### 3) 流式更新与 DOM 状态保持

`updateMessageDOM()` 会替换消息节点。当前已恢复 reasoning 展开状态。若新增可交互折叠区，需在替换前后同步保存/恢复状态。

### 4) HTML 内联加载约束

`_loadHtmlFromAssets()` 通过字符串替换内联 `<link rel="stylesheet" href="style.css">` 与 `<script src="...">`。修改 `index.html` 标签格式时，需确保替换目标仍然匹配。

### 5) 图片代理生命周期

`_LocalImageServer` 是进程级单例，默认不主动停止。若后续需要回收端口，需补充 `stop()` 以及应用生命周期管理策略。

### 6) JS 字符串转义

Flutter `_escJs()` 目前转义 `\`、`'`、换行、回车、制表符。若新增二进制片段或特殊控制字符注入场景，需要扩展转义策略。

### 7) CDN 依赖

marked/highlight/KaTeX/Material Symbols 依赖 CDN。离线场景需切换为本地静态资源并修改 `index.html` 引用。

### 8) 新增消息操作按钮

1. 在 `message_renderer.js`（或 `chat.js`）里补按钮
2. `onclick` 调用 `Bridge.onMessageAction(id, 'newAction')`
3. 在 `chat_detail_page.dart` 的 `_handleMessageAction()` 增加分支

### 9) 代码预览扩展

推荐通过注册表扩展预览语言，不要直接修改判断条件:

```js
window.CodePreviewRegistry.register(
  'svg',
  (code) => code,
  ['image/svg+xml'],
);
```

## Material Symbols 图标约定

全量图标使用 Material Symbols Rounded 字体，通过 `icon(name)` 生成:

```js
function icon(name, extraClass = '') {
  const cls = extraClass ? `ms-icon ${extraClass}` : 'ms-icon';
  return `<span class="${cls}" aria-hidden="true">${name}</span>`;
}
```

图标名称使用 ligature（如 `refresh`、`edit`、`content_copy`、`more_horiz`、`send`、`stop_circle`、`add`、`tune`、`play_arrow`、`visibility`）。
