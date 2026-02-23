# NowChat 插件与 Android Python 运行全解

本文基于当前项目实现（`lib/core/plugin/*`、`lib/providers/plugin_provider.dart`、`android/app/src/main/*`）整理，面向需要开发/安装 Python 插件的维护者。

## 1. 整体架构

NowChat 的插件系统分三层：

1. 分发层（下载/安装）
- `PluginService`：拉取插件清单、下载仓库 zip、解压安装、本地 zip 导入解析。
- 远端清单 `plugin_manifest.json` 当前只保留最小索引：`id` + `repoUrl`。
- 插件完整元数据来自插件仓库内 `plugin.json`（`main/master` 自动尝试）。

2. 状态层（持久化/启停）
- `PluginProvider`：管理安装、卸载、启用/暂停、工具开关、UI 页面加载。
- 安装记录保存在 `SharedPreferences`（key: `plugin_registry_records_v2`）。
- 启动时先恢复本地已安装插件，再后台刷新远端清单（不阻塞首页）。

3. 运行层（工具/Hook/Python）
- `PluginRegistry`：把“已安装且启用”的插件映射为可执行工具与 Hook。
- `PluginRuntimeExecutor`：执行 `python_script/python_inline` 与插件 UI DSL。
- `PluginHookBus`：分发白名单事件（`app_start/chat_before_send/tool_after_execute` 等）。
- `AIToolRuntime`：把插件工具暴露给模型并执行（OpenAI tool-calling 链路）。

### 1.1 这个插件体系用到了哪些技术

1. Flutter 应用层
- Flutter / Dart：应用 UI、状态管理、业务逻辑。
- Provider：插件中心、会话、设置等状态管理。
- Platform Channel：Flutter 与 Android 原生桥接（Python 执行、日志流、保存图片）。

2. Android 原生层
- Kotlin：`MainActivity.kt` 承担 Python 桥接和媒体写入。
- MediaStore：图片保存到系统相册。
- Gradle Kotlin DSL：构建配置（Chaquopy、ABI、签名）。

3. Python 运行层
- Chaquopy：在 Android 进程内运行 Python。
- Python 标准库：执行控制、IO 重定向、超时与 traceback。
- 原生扩展加载：`.so` 动态库预加载（OpenBLAS、gfortran、libcxx 等）。

4. 插件与分发层
- GitHub 仓库分发：通过 `repoUrl` 拉取 zip、`plugin.json`、README。
- JSON 协议：清单、插件定义、工具 schema、Hook payload、UI DSL 页面结构。
- zip 解压安装：本地导入与远端安装统一落地到 `plugin_runtime`。

5. LLM 工具调用层
- OpenAI function calling/tool calling 协议：把插件工具暴露给模型并串行执行。
- Hook 总线：对聊天发送前后、工具执行前后进行可插拔拦截与日志。

### 1.2 技术与代码位置对照表

| 技术 | 在本项目中的用途 | 关键代码位置 |
|---|---|---|
| Flutter Provider | 插件安装/启停/UI 页面状态 | `lib/providers/plugin_provider.dart` |
| Flutter MethodChannel/EventChannel | 执行 Python + 实时日志回传 | `lib/core/plugin/python_plugin_service.dart` |
| Kotlin + Chaquopy | Android 端 Python 桥接 | `android/app/src/main/kotlin/com/nowchat/MainActivity.kt` |
| runner.py | Python 执行、sys.path、超时、日志、so 预加载 | `android/app/src/main/python/runner.py` |
| PluginService | 清单拉取、仓库安装、zip 解析、README 拉取 | `lib/core/plugin/plugin_service.dart` |
| PluginRegistry | 运行时可用插件/工具/路径映射 | `lib/core/plugin/plugin_registry.dart` |
| PluginRuntimeExecutor | `python_script/python_inline` 与 UI DSL 执行 | `lib/core/plugin/plugin_runtime_executor.dart` |
| PluginHookBus | Hook 白名单分发与日志 | `lib/core/plugin/plugin_hook_bus.dart` |
| AIToolRuntime | 工具 schema 导出与工具执行闭环 | `lib/core/tooling/ai_tool_runtime.dart` |
| OpenAI 请求闭环 | tool_calls 解析与多轮继续请求 | `lib/core/network/api_service_requests.part.dart`、`lib/core/network/api_service_streaming.part.dart` |
| Isar | 会话/消息数据存储 | `lib/core/models/*` 与 providers 内 Isar 调用 |

## 2. Android 上如何运行 Python

### 2.1 运行时基础
- Android Gradle 启用 Chaquopy：`android/app/build.gradle.kts`
  - `id("com.chaquo.python")`
  - `chaquopy.defaultConfig.version = "3.10"`
  - ABI 当前固定 `arm64-v8a`

### 2.2 Flutter 与原生桥接
- `MethodChannel`: `nowchat/python_bridge`
  - 方法：`executePython`、`isPythonReady`
- `EventChannel`: `nowchat/python_bridge/log_stream`
  - 实时回传 Python `stdout/stderr` 行日志

原生入口在 `MainActivity.kt`：
- 收到 `executePython` 后启动线程执行。
- 调用 Python 模块 `runner.py` 的 `execute_code(...)`。
- 返回统一结构：`stdout/stderr/exitCode/timedOut/durationMs`。

### 2.3 runner.py 做了什么
- 把 `extraSysPaths` 注入 `sys.path`（执行后恢复）。
- 支持 `working_directory`，避免写到只读根目录。
- 捕获 stdout/stderr。
- 超时控制（线程 join 超时后标记 `timedOut`）。
- 尝试预加载 `.so`，并为 OpenBLAS/Numpy 做兼容处理（减少 `libopenblas.so` 导入失败）。

### 2.4 一次 Python 执行的完整时序（从按钮到结果）

1. Flutter 调 `PythonPluginService.executeCode(...)`。
2. 生成 runId，注册 EventChannel 日志监听。
3. 通过 `MethodChannel(nowchat/python_bridge)` 调到 Android `executePython`。
4. `MainActivity` 新线程调用 `runner.execute_code(...)`。
5. `runner.py` 注入路径、切换 cwd、执行代码、捕获输出。
6. 执行过程中 `print/traceback` 通过 `PythonLogEmitter` 实时回传到 Flutter。
7. 执行完成后返回结构化结果（stdout/stderr/exitCode/timedOut/durationMs）。
8. Flutter 侧把结果用于插件 UI、工具返回或日志展示。

## 3. 插件清单与 plugin.json

## 3.1 市场清单（仓库根）
`plugin_manifest.json` 示例：

```json
{
  "manifestVersion": 2,
  "plugins": [
    { "id": "python_base_libs", "repoUrl": "https://github.com/xxx.git" }
  ]
}
```

说明：
- 只做索引，不再在清单里重复维护工具、包、Hook。
- `PluginService.fetchManifest` 会继续读取每个 repo 的 `plugin.json` 补全信息。

### 3.2 插件定义（插件仓库根 plugin.json）
关键字段：
- 基本信息：`id/name/author/version/description/type`
- Python UI：`pythonNamespace`（配置页入口 = `${pythonNamespace}/schema.py`）
- 依赖插件：`requiredPluginIds`
- 全局路径共享：`providesGlobalPythonPaths`
- 包声明：`packages[]`（`targetDir/pythonPathEntries`）
- 工具声明：`tools[]`（`runtime/scriptPath/inlineCode/parameters/timeoutSec`）
- Hook 声明：`hooks[]`（`event/runtime/scriptPath/priority`）

项目规范要求插件 ID 以 `now_chat_plugin_` 开头（当前代码未做硬校验，属于协作约束）。

### 3.3 `plugin.json` 与运行时行为的对应关系

- `packages[].targetDir`
  - 决定安装后文件落到 `plugin_runtime` 下的相对路径。
- `packages[].pythonPathEntries`
  - 决定执行时注入哪些 `sys.path`。
- `providesGlobalPythonPaths=true`
  - 该插件路径会被注入到其他插件执行环境，适合“基础库插件”。
- `requiredPluginIds`
  - 安装前置检查，不满足则安装被拦截并提示用户。
- `tools[].enabledByDefault`
  - 安装后自动加入已启用工具列表。
- `pythonNamespace`
  - 决定配置页入口文件：`${pythonNamespace}/schema.py`。

## 4. 插件安装与生命周期

### 4.1 启动阶段
`PluginProvider._initialize()`：
1. 创建插件根目录：`<app_support>/plugin_runtime`
2. 创建运行目录：`<plugin_runtime>/runtime`
3. 读取安装记录（本地真值）
4. 扫描磁盘 plugin.json 恢复本地插件
5. 同步 `PluginRegistry`
6. 触发 `app_start` Hook
7. 后台刷新远端清单

### 4.2 安装插件（市场）
`PluginProvider.installPlugin(pluginId)`：
1. 检查 `requiredPluginIds` 是否已安装
2. 优先按 `repoUrl` 安装（下载 repo zip 并扁平解压）
3. 写入 `InstalledPluginRecord`
4. 默认启用 `enabledByDefault=true` 的工具
5. 同步到 `PluginRegistry`

补充：
- 如果仓库 `plugin.json.id` 与清单 `id` 不一致，Provider 会以清单 `id` 为准覆盖，以保证安装记录一致性。
- 安装来源分两类：
  - repo 安装：`remote_plugins/<id>/<version>`
  - 本地导入：`local_plugins/<id>/<version>`

### 4.3 卸载/启停
- 卸载：删除 `packages.targetDir`，清理 UI 状态与缓存。
- 启停：只改安装记录 `enabled`，再同步注册表。

## 5. 工具调用链（LLM -> 插件）

当前工具调用主链在 OpenAI 协议下完整支持（流式/非流式）：

1. `AIToolRuntime.buildOpenAIToolsSchema()` 动态导出已启用工具 schema。
2. 模型返回 `tool_calls`。
3. 宿主串行执行工具 `AIToolRuntime.execute()`。
4. 工具结果作为 `role=tool` 回填继续对话。
5. 记录工具日志（含 status/summary/error/durationMs）。

额外限制：
- 会话开关 `toolCallingEnabled`
- 模型能力 `supportsTools`（来自 provider 的 modelCapabilities）
- 会话上限 `maxToolCalls`

## 6. Hook 事件与改写能力

白名单事件在 `PluginHookBus`：
- `app_start`
- `app_resume`
- `page_enter`
- `page_leave`
- `chat_before_send`
- `chat_after_send`
- `tool_before_execute`
- `tool_after_execute`

消息改写：
- `chat_before_send` / `chat_after_send` 可返回 `{"message": {...}}` 补丁改写消息内容（示例插件会在回复后追加“喵”）。

## 7. 插件配置页（Python UI DSL）

入口：`${pythonNamespace}/schema.py`，必须暴露 `create_page()`。

页面协议：
- `build(payload)`：首屏
- `on_event(event)`：交互后返回下一帧
- 返回结构：`title/subtitle/components/state/message`

当前支持组件：
- `button`
- `text_input`
- `switch`
- `select`

说明：
- Flutter 侧不硬编码插件表单，完全根据 DSL 渲染。
- 插件可在 `base.py` 提供父类封装，提升开发体验。

## 8. 安装新的 Python 插件

### 8.1 远端安装（推荐）
1. 建一个 GitHub 仓库，根目录放 `plugin.json` + 脚本。
2. 在主仓库 `plugin_manifest.json` 增加：
   - `id`
   - `repoUrl`
3. 刷新插件清单后在插件中心安装。

### 8.2 本地 zip 导入（代码支持）
- zip 根目录必须直接包含 `plugin.json`。
- 当前 UI 暂时隐藏导入入口（`plugin_page.dart` 有注释），但服务端逻辑仍支持。

### 8.3 推荐的最小目录模板

```text
your_plugin/
  plugin.json
  README.md
  hooks/
    app_start.py
  tools/
    your_tool.py
  your_plugin_ui/
    __init__.py
    base.py
    schema.py
```

关键点：
- `type` 建议 `python`
- `pythonNamespace` 要和 `your_plugin_ui` 保持一致
- `schema.py` 必须有 `create_page()`
- 工具脚本建议提供 `main(payload)`

## 9. 给插件安装 Python 库（重点）

### 9.1 纯 Python 库
- 直接把库文件放到插件目录（如 `libs/`）。
- 在 `plugin.json -> packages[].pythonPathEntries` 增加路径（如 `"libs"`）。

### 9.2 原生扩展库（.so）
必须与运行时匹配：
- Python: 3.10（当前 Chaquopy）
- ABI: arm64-v8a
- Android 平台标签建议：`android_24_arm64_v8a`

下载 wheel 示例（按需改包名）：

```powershell
py -3.11 -m pip download matplotlib==3.6.0 --dest .\wheels `
  --only-binary=:all: `
  --platform android_24_arm64_v8a `
  --python-version 3.10 `
  --implementation cp `
  --abi cp310 `
  --index-url https://chaquo.com/pypi-13.1/
```

注意：
- 某些库（如 `scipy/statsmodels`）在目标平台可能无 wheel。
- Numpy/Pandas 常需额外依赖（如 OpenBLAS、libgfortran、libcxx）。
- 缺依赖时会报 `dlopen failed: library ... not found`。

### 9.3 原生库安装常见策略

1. 基础能力插件
- 例如 `python_base_libs`：提供 `numpy/pandas/openblas` 等共享依赖。
- 设置 `providesGlobalPythonPaths=true`，给其他插件复用。

2. 专项能力插件
- 例如 `python_chart_libs`：只放图表相关库（matplotlib、seaborn、plotly...）。
- 通过 `requiredPluginIds` 依赖基础库插件，避免重复打包大体积基础依赖。

3. 失败排查思路
- 先看 `sys.path` 是否包含预期目录。
- 再看 `.so` 文件是否存在且 ABI/py 版本匹配。
- 最后看是否遗漏依赖链（openblas -> gfortran -> cxx）。

## 10. 路径与数据落盘

常见目录（Android）：
- 插件根：`<app_support>/plugin_runtime`
- 远端插件：`plugin_runtime/remote_plugins/<pluginId>/<version>`
- 本地插件：`plugin_runtime/local_plugins/<pluginId>/<version>`
- 运行目录：`plugin_runtime/runtime/<pluginId>`

图表类工具建议将产物写入 runtime 目录，而不是插件目录本身。

## 11. 镜像与网络

GitHub 拉取支持镜像策略（统一配置在 `GithubMirrorConfig`）：
- direct
- ghfast.top
- gh.llkk.cc
- ghproxy.net
- custom（用户自定义）

插件清单拉取、repo 下载、README/plugin.json 拉取都走这套镜像逻辑。

## 12. 日志与调试

Python 执行日志会同时进入：
- Logcat（tag: `NowChatPython`，前缀 `[PyRT]`）
- Flutter `AppLogger`

建议调试顺序：
1. 看插件中心/详情页错误提示
2. 看 AppLogger 中 `PluginHook`、`ToolUsage`、`PyRT`
3. 看 Logcat 中 Python traceback

补充：
- Python 长日志会在 Flutter 侧分片输出（避免单条超长日志丢失）。
- `tool_after_execute` payload 会包含 `toolMessageContent`，插件可据此打印完整工具返回值。

## 13. 常见问题速查

1. `Python 插件缺少 pythonNamespace`
- 原因：`plugin.json` 没填 `pythonNamespace`。

2. `ModuleNotFoundError: No module named xxx`
- 原因：`pythonPathEntries` 或 UI 命名空间路径配置错误。

3. `libopenblas.so not found`
- 原因：原生依赖未打包完整或路径未加入。

4. `Read-only file system`
- 原因：脚本写入了只读目录（如 `/chart_outputs`）。
- 解决：使用 `workingDirectory`/runtime 目录写入。

5. 插件安装时报 `ID 不匹配`
- 原因：清单 `id` 与仓库 `plugin.json.id` 不一致。

## 14. 安全边界（必须了解）

当前 Python 插件能力较强，不是强沙箱：
- 可执行任意 Python 代码。
- 可读写应用私有目录中的插件/运行时文件。
- 可发起网络请求（取决于代码与权限）。

建议：
- 仅安装可信仓库插件。
- 插件上线前做代码审计。
- 对高风险能力（网络/文件/Hook 改写）做最小化设计。

## 15. 关键代码入口索引

- 插件分发：`lib/core/plugin/plugin_service.dart`
- 插件状态：`lib/providers/plugin_provider.dart`
- 运行时执行：`lib/core/plugin/plugin_runtime_executor.dart`
- 注册表：`lib/core/plugin/plugin_registry.dart`
- Hook 总线：`lib/core/plugin/plugin_hook_bus.dart`
- 工具运行：`lib/core/tooling/ai_tool_runtime.dart`
- Android 桥接：`android/app/src/main/kotlin/com/nowchat/MainActivity.kt`
- Python 执行器：`android/app/src/main/python/runner.py`
- 清单索引：`plugin_manifest.json`

## 16. 官方文档与资料入口（按技术分类）

### 16.1 Flutter / Dart / 状态管理
- Flutter 官方文档：https://docs.flutter.dev/
- Dart 官方文档：https://dart.dev/
- Flutter Platform Channels：https://docs.flutter.dev/platform-integration/platform-channels
- MethodChannel API：https://api.flutter.dev/flutter/services/MethodChannel-class.html
- EventChannel API：https://api.flutter.dev/flutter/services/EventChannel-class.html
- Provider（pub.dev）：https://pub.dev/packages/provider
- SharedPreferences（pub.dev）：https://pub.dev/packages/shared_preferences
- Path Provider（pub.dev）：https://pub.dev/packages/path_provider

### 16.2 网络与数据
- Dio（pub.dev）：https://pub.dev/packages/dio
- http（pub.dev）：https://pub.dev/packages/http
- Isar 文档：https://isar.dev/
- Isar Flutter libs（pub.dev）：https://pub.dev/packages/isar_flutter_libs

### 16.3 Android 原生与媒体
- Android 官方文档：https://developer.android.com/docs
- MediaStore 官方文档：https://developer.android.com/reference/android/provider/MediaStore
- Kotlin 官方文档：https://kotlinlang.org/docs/home.html
- Gradle Kotlin DSL：https://docs.gradle.org/current/userguide/kotlin_dsl.html

### 16.4 Android 运行 Python
- Chaquopy 官方文档：https://chaquo.com/chaquopy/doc/current/
- Chaquopy PyPI 索引说明（文档内 PyPI 章节）：https://chaquo.com/chaquopy/doc/current/python.html
- Python 官方文档：https://docs.python.org/3/
- pip 官方文档：https://pip.pypa.io/en/stable/

### 16.5 LLM Tool Calling 协议
- OpenAI API 文档（工具调用）：https://platform.openai.com/docs/api-reference/chat/create
- OpenAI 函数调用概念文档：https://platform.openai.com/docs/guides/function-calling

### 16.6 其他项目中实际用到的库
- logger：https://pub.dev/packages/logger
- file_picker：https://pub.dev/packages/file_picker
- archive（zip 解压）：https://pub.dev/packages/archive
- crypto（SHA256）：https://pub.dev/packages/crypto
- path：https://pub.dev/packages/path

## 17. 文档查询建议（最快路径）

1. 先看本项目代码入口
- 看 `PluginProvider` 确认“行为入口”。
- 看 `PluginRuntimeExecutor` 确认“执行协议”。
- 看 `MainActivity.kt` + `runner.py` 确认“原生桥接”。

2. 再看对应官方文档
- 如果是 Flutter 问题：先看 Flutter API 文档。
- 如果是 Python 运行问题：先看 Chaquopy 文档，再看 Python 官方文档。
- 如果是模型工具调用问题：看 OpenAI tool calling 文档。

3. 最后看日志定位
- `AppLogger` + Logcat + traceback 联合看，比单看 UI 报错更快。
