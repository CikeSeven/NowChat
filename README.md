# Now Chat

Now Chat 是一款面向移动端的多模型 AI 聊天应用，支持多提供方接入、会话级参数配置、智能体（Agent）能力，以及图片/文件输入。

项目地址：`https://github.com/CikeSeven/NowChat`

## 界面截图
| 会话列表页 | API 管理页 |
| --- | --- |
| <img src="https://github.com/user-attachments/assets/aa6dd126-70b2-416f-abde-a36d43ca452a" width="220" /> | <img src="https://github.com/user-attachments/assets/5ce9eabb-9466-4497-af84-86d6363e287e" width="220" /> |

| 新增/编辑 API 页 | 聊天详情页 |
| --- | --- |
| <img src="https://github.com/user-attachments/assets/e27a9af7-74b1-4ca4-95ee-08e62fcb3253" width="220" /> | <img src="https://github.com/user-attachments/assets/d144362f-379c-44ec-a4d8-3fafd14a5d7a" width="220" /> |

| 会话设置页 | 智能体页面 |
| --- | --- |
| <img src="https://github.com/user-attachments/assets/e94b7ba8-3774-402c-bbfb-02ee9cb14dd6" width="220" /> | <img src="https://github.com/user-attachments/assets/d898e298-1693-47cf-a550-d4ae2177dc7b" width="220" /> |

## 主要功能
- 多提供方与多协议支持：OpenAI、Gemini、Claude、DeepSeek、Ollama 等。
- API 管理：获取模型、手动添加自定义模型、模型备注、视觉/工具能力标记。
- 聊天增强：流式输出、重新发送、中断与继续生成、Markdown 渲染。
- 会话设置：支持会话级 `System Prompt`、`Temperature`、`top_p`、`max_tokens`、最大消息轮次。
- 智能体（Agent）：可创建一次性任务型智能体（如翻译助手），并单独配置参数。
- 附件能力：支持图片与文件上传，按模型能力自动限制可用入口。

## 使用流程
1. 在 `API` 页面添加提供方并填写 `API Key`、`Base URL`、请求方式。
2. 点击 `获取模型`，从“可添加模型”中选择，或手动添加模型。
3. 回到 `会话` 页面新建对话，选择模型后开始聊天。
4. 在会话设置中调整参数，保存为当前会话专用配置。
5. 在 `智能体` 页面创建任务型 Agent，输入一次性指令获取结果。

## 数据与隐私
- 会话与消息保存在本地（Isar）。
- API 配置保存在本地（SharedPreferences）。
- 仅在你主动发起请求时，应用才会将必要内容发送到你选择的 API 服务端。

## 常见问题
### 获取模型失败或超时
- 检查 `Base URL`、API Key、请求方式和网络连通性。
- 部分平台需要确认模型列表接口权限是否开通。

### 模型返回 4xx/5xx
- 常见原因是协议不匹配、模型无权限，或请求内容超出模型能力（如视觉输入）。
