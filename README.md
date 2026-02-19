# NowChat

NowChat 是一款面向 Android 的多模型 AI 客户端，主打本地会话管理、灵活 API 接入、工具调用和插件扩展。

## 功能概览
- 多提供方接入：OpenAI 兼容、Gemini、Claude 及更多国内外模型服务。
- API 管理：按提供方维护 Key、Base URL、请求方式，支持拉取模型和手动添加自定义模型。
- 会话参数：会话级 `System Prompt`、`temperature`、`top_p`、`max_tokens`、最大消息轮次。
- 生成控制：流式输出、重新生成、手动中断、继续生成。
- 多模态输入：按模型能力启用图片/文件上传入口。
- 工具调用：支持模型调用工具并显示调用日志。
- 插件中心：安装/启用/暂停/卸载插件，插件可扩展工具、Hook 与配置页面。

## 页面导航
- `会话`：日常聊天、历史会话、会话设置。
- `工具`：一次性任务型工具页（如翻译、改写等）。
- `API`：管理模型提供方与模型列表。
- `设置`：主题、默认参数、关于、插件入口等。

## 使用步骤
1. 打开 `API` 页面，先添加一个提供方配置。
2. 点击 `获取模型` 拉取模型，或手动输入模型名并保存。
3. 回到 `会话` 页面新建聊天，选择模型后发送消息。
4. 在会话右上角进入设置，按当前会话单独调整参数。
5. 需要扩展能力时进入插件中心，安装并启用所需插件。

## 界面截图
| 会话列表 | API 管理 |
| --- | --- |
| <img src="https://github.com/user-attachments/assets/aa6dd126-70b2-416f-abde-a36d43ca452a" width="220" /> | <img src="https://github.com/user-attachments/assets/5ce9eabb-9466-4497-af84-86d6363e287e" width="220" /> |

| 编辑 API | 聊天详情 |
| --- | --- |
| <img src="https://github.com/user-attachments/assets/e27a9af7-74b1-4ca4-95ee-08e62fcb3253" width="220" /> | <img src="https://github.com/user-attachments/assets/d144362f-379c-44ec-a4d8-3fafd14a5d7a" width="220" /> |

| 会话设置 | 工具页 |
| --- | --- |
| <img src="https://github.com/user-attachments/assets/e94b7ba8-3774-402c-bbfb-02ee9cb14dd6" width="220" /> | <img src="https://github.com/user-attachments/assets/d898e298-1693-47cf-a550-d4ae2177dc7b" width="220" /> |

## 插件系统
- 插件支持工具扩展、事件 Hook、插件专属配置页面。
- 插件支持启用/暂停，已安装插件可重新安装或卸载。
- Python 插件执行日志支持实时输出，便于排查脚本行为。

## 数据与隐私
- 会话、消息、会话参数保存在本地数据库。
- API 配置与插件状态保存在本地。
- 应用仅在你主动发送请求时，向你配置的模型服务端发送必要数据。

## 常见问题
### 1. 获取模型失败/超时
- 检查 API Key、Base URL、请求方式是否匹配。
- 确认网络可访问对应服务，以及账号是否有模型列表权限。

### 2. 返回 4xx/5xx
- 多数是协议不匹配、模型无权限、或参数超限导致。
- 优先检查请求方式、模型名、`max_tokens`、工具调用开关。

### 3. 插件无法执行
- 确认插件已安装且状态为“运行中”。
- 打开日志查看插件实时输出，优先排查脚本报错与依赖缺失。
