package com.sis.nowchat.viewmodel

import android.app.Application
import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.sis.nowchat.data.ChatRequest
import com.sis.nowchat.data.MessageRole
import com.sis.nowchat.model.APIModel
import com.sis.nowchat.model.Message
import com.sis.nowchat.model.toRequestMessage
import com.sis.nowchat.service.ChatService
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.io.File

class MessageViewModel(
    appContext: Context,
    private val chatService: ChatService = ChatService()
) : ViewModel() {
    private val _chatMessages = MutableStateFlow<List<Message>>(emptyList())
    val chatMessages: StateFlow<List<Message>> = _chatMessages

    //存储是否正在回答问题的状态
    private val _isResponding = MutableStateFlow(false)
    val isResponding: StateFlow<Boolean> = _isResponding
    // 对话记录存储目录
    private val conversationsDir = File(appContext.filesDir, "conversations")


    /**
     * 根据对话 ID 加载聊天记录
     */
    fun loadMessagesForConversation(conversationId: String?) {
        // 为null则代表新对话，清空对话记录
        if (conversationId == null) {
            _chatMessages.value = emptyList()
        }else {
            viewModelScope.launch(Dispatchers.IO) {
                val folder = File(conversationsDir, conversationId)
                val messageFile = File(folder, "messages.json")

                if (messageFile.exists()) {
                    try {
                        val jsonString = messageFile.readText()
                        val type = object : TypeToken<List<Message>>() {}.type
                        val messages = Gson().fromJson<List<Message>>(jsonString, type)
                        _chatMessages.value = messages
                        println("加载id: $conversationId 消息列表: ${_chatMessages.value}")
                    }catch (e: Exception) {
                        e.printStackTrace()
                    }
                }else {
                    _chatMessages.value = emptyList()
                }
            }
        }
    }

    /**
     * 保存聊天记录到文件
     */
    fun saveMessagesForConversation(conversationId: String, messages: List<Message>) {
        viewModelScope.launch(Dispatchers.IO) {
            val folder = File(conversationsDir, conversationId)
            if (!folder.exists()) {
                folder.mkdirs()
            }

            val messagesFile = File(folder, "messages.json")
            val jsonString = Gson().toJson(messages)
            messagesFile.writeText(jsonString)
        }
    }

    /**
     * 更新消息
     */
    fun updateMessage(message: Message) {
        val updatedList = _chatMessages.value.map {
            if (it.id == message.id) message else it
        }
        _chatMessages.value = updatedList
    }

    fun addMessage(message: Message) {
        _chatMessages.value += message
    }

    /**
     * 删除指定消息
     */
    fun deleteMessage(message: Message) {
        _chatMessages.value = _chatMessages.value.filter { it != message }
    }

    /**
     * 删除指定消息及其之后的所有消息
     */
    fun deleteMessageAfter(message: Message) {
        val currentIndex = _chatMessages.value.indexOf(message)
        if (currentIndex != -1) {
            _chatMessages.value = _chatMessages.value.take(currentIndex)
        }
    }

    /**
     * 删除消息列表中的最后一条消息
     */
    private fun deleteLastMessage() {
        val updatedList = _chatMessages.value.dropLast(1)
        _chatMessages.value = updatedList
    }


    private var currentAiResponse = StringBuilder()
    private var currentReasoningResponse = StringBuilder()

    // 当前的协程任务
    private var currentJob: Job? = null
    // 思考时间计时
    private var isThinking = false
    private var timerJob: Job? = null
    fun sendMessage(apiModel: APIModel, regenerate: Boolean = false, conversationId: String) {
        currentJob = viewModelScope.launch {
            try {
                if (regenerate) {
                    val lastMessage = _chatMessages.value.lastOrNull()
                    if (lastMessage?.role == MessageRole.ASSISTANT) {
                        deleteLastMessage()
                    }
                }
                _isResponding.value = true
                // 保存聊天记录到文件
                saveMessagesForConversation(conversationId, _chatMessages.value)
                val messages = _chatMessages.value.map { it.toRequestMessage() }
                val chatRequest = ChatRequest(
                    model = apiModel.getCurrentModel(),
                    messages = messages,
                    stream = true,
                    url = if (apiModel.apiPath.endsWith("/")) "${apiModel.apiUrl}${apiModel.apiPath}" else "${apiModel.apiUrl}${apiModel.apiPath}/",
                    api_key = apiModel.apiKey
                )

                currentAiResponse.clear()
                currentReasoningResponse.clear()
                if (_chatMessages.value[_chatMessages.value.size - 1].role != MessageRole.ASSISTANT) {
                    // 占位AI的消息
                    _chatMessages.value += Message(role = MessageRole.ASSISTANT, content = "")
                }

                // 记录思考时间的变量
                var thinkStartTime: Long

                chatService.sendMessageStream(chatRequest).collect { partialResponse ->
                    if (partialResponse.startsWith("[Reasoning]")) {
                        // 如果是思考内容，启动计时器
                        val reasoningContent = partialResponse.removePrefix("[Reasoning]")
                        currentReasoningResponse.append(reasoningContent)

                        // 如果是第一个思考内容，启动计时器
                        if (!isThinking) {
                            isThinking = true
                            thinkStartTime = System.nanoTime()
                            timerJob = viewModelScope.launch {
                                while (isThinking) {
                                    val thinkTimeInSeconds = ((System.nanoTime() - thinkStartTime) / 1_000_000_000f * 10).toInt() / 10f
                                    updateLastMessage(conversationId, thinkTime = thinkTimeInSeconds)
                                    kotlinx.coroutines.delay(100) // 每隔 100 毫秒更新一次
                                }
                            }
                        }
                        updateLastMessage(conversationId, thinkContent = currentReasoningResponse.toString())
                    }else {
                        // 如果是普通内容
                        currentAiResponse.append(partialResponse)
                        // 停止计时器
                        isThinking = false
                        timerJob?.cancel() // 取消计时器协程
                        // 更新最后一条消息
                        updateLastMessage(
                            conversationId,
                            content = currentAiResponse.toString()
                        )
                    }
                }
            }catch (e: CancellationException) {
                println("Coroutine cancelled")
            }
            catch (e: Exception) {
                // 处理错误
                updateLastMessage(conversationId, content = "Error: ${e.message}")
            }finally {
                // 确保无论成功还是失败，都设置为未回答状态
                _isResponding.value = false
            }
        }
    }

    /**
     * 计算思考时间
     */
    private fun calculateThinkTime(startTime: Long): Float {
        val endTime = System.nanoTime()
        val timeInSeconds = (endTime - startTime) / 1_000_000_000f
        return (timeInSeconds * 10).toInt() / 10f // 保留小数点后一位
    }

    /**
     * 更新最后一条消息的内容
     */
    private fun updateLastMessage(conversationId: String, content: String? = null, thinkContent: String? = null, thinkTime: Float? = null) {
        val lastMessage = _chatMessages.value.lastOrNull() ?: return

        // 创建更新后的消息
        val updatedMessage = lastMessage.copy(
            content = content ?: lastMessage.content,
            thinkContent = thinkContent ?: lastMessage.thinkContent,
            thinkTime = thinkTime ?: lastMessage.thinkTime
        )

        // 替换最后一条消息
        val updatedList = _chatMessages.value.dropLast(1) + updatedMessage
        _chatMessages.value = updatedList

        // 更新消息后保存到文件
        saveMessagesForConversation(conversationId, _chatMessages.value)
    }

    /**
     * 断开连接，停止接收消息
     */
    fun disconnect() {
        // 停止计时器
        isThinking = false
        timerJob?.cancel() // 取消计时器协程
        // 取消当前的协程任务
        currentJob?.cancel()
        // 调用 ChatService 的断开逻辑
        chatService.cancelStream()
        // 设置为未回答状态
        _isResponding.value = false
    }

}