# NowChat 插件系统与 Python 运行指南

本文基于当前仓库实现整理，面向插件开发者与维护者。

## 1. 文档范围

本文覆盖以下能力：

1. 插件市场清单与 `plugin.json` 规范。
2. 插件安装路径（仓库安装 / 本地 zip 导入 / 同 ID 覆盖安装）。
3. Python requirements 运行时安装机制。
4. Tool / Hook / Python UI DSL 的运行链路。
5. 排障与验证清单。

## 2. 系统分层

NowChat 插件体系由三层组成：

1. 分发层：清单拉取、仓库下载、zip 解析与安装。
2. 状态层：安装记录、启停状态、启用工具集合。
3. 运行层：工具执行、Hook 分发、Python UI DSL 渲染。

核心文件：

- `lib/core/plugin/plugin_service.dart`
- `lib/providers/plugin_provider.dart`
- `lib/core/plugin/plugin_registry.dart`
- `lib/core/plugin/plugin_runtime_executor.dart`
- `lib/core/plugin/plugin_hook_bus.dart`
- `lib/core/plugin/python_plugin_service.dart`
- `lib/core/tooling/ai_tool_runtime.dart`

## 3. 清单与插件定义

### 3.1 远端市场清单

文件：`plugin_manifest.json`

当前清单采用最小索引结构：

- `id`
- `repoUrl`

插件完整信息（名称、版本、工具、Hook、requirements 等）以插件仓库中的 `plugin.json` 为准。

### 3.2 plugin.json 关键字段

最常用字段：

- `id`：插件唯一标识。
- `name` / `author` / `description` / `version` / `type`。
- `requirements`：运行时安装依赖列表。
- `pythonNamespace`：配置页入口命名空间，入口文件为 `${pythonNamespace}/schema.py`。
- `providesGlobalPythonPaths`：是否向其他插件暴露自身 Python 路径。
- `packages[]`：插件包落地目录与 Python 路径声明。
- `tools[]`：模型可调用工具定义。
- `hooks[]`：事件钩子定义。
- `permissions[]`：权限声明。

项目约束：插件 `id` 应以 `now_chat_plugin_` 开头。

## 4. 安装与覆盖流程

### 4.1 仓库安装（插件中心）

调用链：`PluginProvider.installPlugin -> PluginService.installPluginFromRepo`

行为：

1. 下载仓库压缩包（自动尝试 `main/master`）。
2. 解压并去掉 GitHub 顶层目录。
3. 解析插件定义。
4. 如声明 `requirements`，安装到插件目录下 `__requirements__`。
5. 写入安装记录并同步运行时注册表。

默认目录：

- 远端安装：`plugin_runtime/remote_plugins/<pluginId>/<version>`

### 4.2 本地 zip 导入

调用链：`pickLocalPluginImportPayload -> importLocalPluginPayload`

规则：

1. 仅支持 `zip`。
2. zip 根目录必须直接包含 `plugin.json`。
3. 导入前先解析元信息，再执行安装。

默认目录：

- 本地安装：`plugin_runtime/local_plugins/<pluginId>/<version>`

### 4.3 同 ID 覆盖安装

当前实现已支持同 ID 覆盖确认（UI 弹窗显示旧版本与导入版本）。

覆盖策略：

1. 若旧记录存在且 `requirements` 签名一致，复用旧 `__requirements__` 目录。
2. 若 requirements 不一致，重装依赖。
3. 清理旧版本中不再需要的包目录，避免脏数据残留。
4. 更新安装记录并同步注册表。

## 5. Python requirements 机制

requirements 安装由 `PythonPluginService.installRequirements` 执行。

### 5.1 安装位置

每个插件版本独立保存依赖目录：

- `<plugin_target_dir>/__requirements__`

并生成 lock 文件：

- `<plugin_target_dir>/plugin_requirements_lock.json`

### 5.2 镜像与回退

默认镜像链路：

1. Chaquopy 源（`direct`）
2. 若解析失败，回退到 PyPI simple（清华 -> 官方）

实现文件：`lib/core/network/python_package_mirror_config.dart`

### 5.3 传递依赖

安装器会读取 wheel metadata 的 `Requires-Dist`，并继续解析传递依赖。

说明：

1. 支持常见 marker 过滤（`python_version/sys_platform/platform_system/os_name/extra`）。
2. 复杂 marker 无法解析时采用“尽量不漏装”的保守策略。
3. 回退到 PyPI 时仅接受纯 Python wheel（如 `py3-none-any`），减少 ABI 不兼容风险。

### 5.4 lock 文件内容

`plugin_requirements_lock.json` 记录：

- 插件 ID、解析时间、目标目录、requirements 原文。
- 使用的镜像链与 PyPI 回退链。
- 每个包的版本、来源、索引 URL、下载 URL、sha256、依赖发现记录、回退尝试记录。

## 6. 运行时链路

### 6.1 工具调用链

1. 模型返回 `tool_calls`。
2. `AIToolRuntime` 分发到插件工具。
3. `PluginRuntimeExecutor` 执行 `python_script/python_inline`。
4. `PythonPluginService` 通过 MethodChannel 调用 Android 侧 Python 桥。
5. 结果回填 `role=tool`，继续请求模型。

受会话参数约束：

- `toolCallingEnabled`
- `maxToolCalls`

### 6.2 Hook 事件链

`PluginHookBus` 分发白名单事件（如 `app_start`、`chat_before_send`、`tool_after_execute`）。

`chat_before_send` / `chat_after_send` 可通过 `{"message": {...}}` 补丁改写消息。

### 6.3 Python UI DSL

入口：`${pythonNamespace}/schema.py`

要求：

1. 必须提供 `create_page()`。
2. 页面对象实现 `build(payload)` 与 `on_event(event)`。
3. Flutter 侧按 DSL 结构动态渲染。

## 7. 日志与观测

重点日志来源：

- `AppLogger`（Flutter）
- Logcat `NowChatPython`（Python 侧 stdout/stderr）
- Hook 执行日志（`PluginHook(...)`）
- Tool 执行日志（`ToolUsage END ...`）

排障建议：

1. 先看插件安装日志（清单、下载、解压、requirements）。
2. 再看工具执行日志（输入、summary、errorType）。
3. 最后看 Python stdout/stderr 原文。

## 8. 常见问题

### 8.1 导入失败：zip 不合法

原因：zip 根目录缺少 `plugin.json`。

### 8.2 requirements 安装失败

优先检查：

1. 当前镜像可达性。
2. 包是否存在可用 wheel。
3. lock 中是否有失败候选与回退记录。

### 8.3 工具可安装但运行失败

优先检查：

1. `pythonNamespace` / `scriptPath` 路径是否正确。
2. `packages[].pythonPathEntries` 是否覆盖脚本目录。
3. requirements 是否安装到对应插件版本目录。

## 9. 开发与发布检查清单

1. `plugin.json` 字段完整且语义正确。
2. 插件 ID 符合命名规范（`now_chat_plugin_` 前缀）。
3. 工具参数 schema、超时、输出上限已设置。
4. Hook 仅使用白名单事件。
5. requirements 安装与 lock 结果可复现。
6. 工具与 Hook 日志可观测。
7. 本地 zip 导入、仓库安装、同 ID 覆盖安装均验证通过。
