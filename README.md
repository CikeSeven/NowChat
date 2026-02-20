# NowChat

NowChat 是一款面向 Android 的多模型 AI 客户端，支持自定义 API、会话参数、工具调用与插件扩展。

## 功能概览
- 多模型接入：支持 OpenAI 兼容接口，以及 Gemini、Claude、国内常见模型服务等。
- API 管理：可配置多提供方，支持拉取模型、手动添加模型、自定义模型备注名。
- 会话参数：支持会话级 `System Prompt`、`temperature`、`top_p`、`max_tokens`、最大消息轮次。
- 流式体验：支持中断生成、继续生成、重发最后一条回复。
- 工具调用：支持模型调用工具，并提供调用日志。
- 插件系统：支持插件安装/启用/暂停/卸载，插件可扩展工具、Hook 和配置页面。
- 图片体验：支持 Markdown 图片预览，支持保存图片到系统相册。
- 数据管理：支持导入/导出会话、工具、API 配置（可选包含 API Key）。
- 版本更新：关于页可检查新版本，自动尝试可用代理访问更新信息。

## 页面导航
- 会话：日常聊天、历史会话、会话设置。
- 工具：一次性任务型工具页（如翻译、提取、改写等）。
- API：管理模型提供方、请求方式、模型列表。
- 设置：主题、默认参数、插件中心、数据管理、关于。

## 快速上手
1. 打开 `API` 页面，添加至少一个可用提供方。
2. 点击 `获取模型` 拉取模型，或手动添加模型。
3. 回到 `会话` 页面新建聊天，选择模型后发送消息。
4. 在会话设置中按需调整当前会话参数。
5. 需要扩展能力时，前往 `设置 -> 插件中心` 安装并启用插件。

## 界面截图
| 会话列表 | API 管理 | 编辑 API |
| --- | --- | --- |
| <img src="https://github.com/user-attachments/assets/833604c3-7021-4ed5-81d2-2b1abe8605b1" width="220" /> | <img src="https://github.com/user-attachments/assets/905fc33e-6383-46ca-b520-1db9ac320c62" width="220" /> | <img src="https://github.com/user-attachments/assets/b045ca75-1fef-4920-960d-578f2479011b" width="220" /> |

| 聊天详情 | 会话设置 | 工具页 |
| --- | --- | --- |
| <img src="https://github.com/user-attachments/assets/6300f64d-b44a-425f-93b1-976e9645fd8b" width="220" /> | <img src="https://github.com/user-attachments/assets/7af1a4ae-b50b-43a2-b4c3-0291be3ee18b" width="220" /> | <img src="https://github.com/user-attachments/assets/f559fde1-413a-4abd-9c10-f2fdac5adaab" width="220" /> |

| 插件中心 | 设置页 | 
| --- | --- | 
| <img src="https://github.com/user-attachments/assets/7b5693d5-4fa1-4b9e-99db-d9c29d03af5b" width="220" /> | <img src="https://github.com/user-attachments/assets/db5ab4ff-eced-4c10-a10c-63a4b66f4b22" width="220" /> |





## 插件说明
- 插件市场与已安装插件分栏展示，支持搜索。
- 支持前置插件依赖检查，缺失前置时会阻止安装并提示。
- 支持 GitHub 镜像访问与测速，适配不同网络环境。
- Python 插件支持实时日志输出，便于定位问题。

## 数据与隐私
- 会话、消息、工具配置、API 配置默认保存在本地。
- 仅在你主动发送请求时，应用才会把必要内容发送到你配置的模型服务。
- 数据导入为覆盖式操作，建议先导出备份。

## 常见问题
### 1. 获取模型失败或超时
- 检查 API Key、Base URL、请求方式是否匹配。
- 检查网络是否能访问对应服务。

### 2. 插件下载失败
- 在插件中心切换镜像后重试。
- 检查插件仓库地址与插件信息文件是否有效。

### 3. 返回 4xx/5xx 或回复异常中断
- 常见原因是模型权限、协议不匹配或参数超限。
- 优先检查模型名、请求方式、会话参数和工具开关。
