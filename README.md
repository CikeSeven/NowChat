# Now Chat

一个面向移动端（Android / iOS）的多模型聊天应用。  
支持多个 API 提供方、会话级参数、自定义模型管理、流式输出，以及图片/文件作为上下文输入。

## 界面预览
| 会话列表页 | API 管理页 |
| --- | --- |
| <img src="https://github.com/user-attachments/assets/aa6dd126-70b2-416f-abde-a36d43ca452a" width="220" /> | <img src="https://github.com/user-attachments/assets/5ce9eabb-9466-4497-af84-86d6363e287e" width="220" /> |

| 新增/编辑 API 页 | 聊天详情页 |
| --- | --- |
| <img src="https://github.com/user-attachments/assets/e27a9af7-74b1-4ca4-95ee-08e62fcb3253" width="220" /> | <img src="https://github.com/user-attachments/assets/d144362f-379c-44ec-a4d8-3fafd14a5d7a" width="220" /> |

| 会话设置页 |
| --- |
| <img src="https://github.com/user-attachments/assets/e94b7ba8-3774-402c-bbfb-02ee9cb14dd6" width="220" /> |

## 核心功能

- 多提供方支持：内置 OpenAI、Gemini、Claude、DeepSeek、Ollama，以及常见国内/兼容平台预设。
- 多请求方式：支持 `OpenAI Chat Completions`、`Gemini GenerateContent`、`Claude Messages`。
- API 管理：可搜索、编辑、删除提供方；支持获取模型列表和手动添加自定义模型。
- 模型增强：支持模型备注名（聊天页显示备注），并可标记“支持视觉 / 支持工具”能力。
- 会话级参数：每个会话可单独配置 `System Prompt`、`Temperature`、`top_p`、`max_tokens`、流式开关。
- 发送附件：支持上传图片和文件，并在输入区预览；根据模型能力控制上传入口。
- 消息体验：支持 Markdown 渲染、代码块复制、仅最后一条 AI 消息显示“重新发送”。

## 使用说明

### 1. 添加 API 提供方

1. 进入底部导航 `API` 页。
2. 点击 `添加 API`。
3. 选择预设提供方，填写 `API Key`，确认 `Base URL` 和请求路径。
4. 点击右上角 `保存`。

### 2. 管理模型

1. 在 API 编辑页点击 `获取模型` 拉取模型列表。
2. 可直接从“可添加模型”加入，或点击 `手动添加` 输入自定义模型名。
3. 可为模型设置备注名（聊天页显示优先使用备注名）。
4. 可为模型开启能力标记：
   - 支持视觉：允许图片按多模态方式发送。
   - 支持工具：允许文件上传入口可用。

### 3. 开始会话

1. 进入 `会话` 页，新建会话。
2. 在聊天页底部点击模型区域，选择提供方与模型。
3. 输入消息后发送；可按需开启/关闭流式输出。

### 4. 会话设置

聊天页右上角进入会话设置，可配置：

- 人格设置 / `System Prompt`（会在会话顶部展示，并参与每次请求）
- `Temperature`
- `top_p`
- `max_tokens`
- 流式输出开关

### 5. 附件发送

- 左下角 `+` 可上传图片或文件。
- 图片会显示缩略图预览，文件显示文件名。
- 若当前模型未开启对应能力，会给出提示并阻止该类型上传。

## 数据与隐私

- 会话与消息保存在本地数据库（Isar）。
- API 配置保存在本地（SharedPreferences）。
- 应用不会自动上传本地数据到第三方服务；仅在你发起请求时向所选 API 提供方发送必要内容。

## 常见问题

### 获取模型超时

模型列表请求带有超时保护（15 秒）。若超时，请检查网络、Base URL、Key 权限与服务状态。

### 部分模型返回 4xx/5xx

常见原因：

- 请求方式与模型不匹配（例如接口协议不一致）。
- 模型本身不支持你当前发送的内容格式（如图片输入）。
- 账号或 Key 对该模型没有权限。

建议优先核对：请求方式、模型能力标记、路径和鉴权配置。
