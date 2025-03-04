package com.sis.nowchat.viewmodel

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.gson.Gson
import com.sis.nowchat.model.Conversation
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.io.File

class ConversationViewModel(appContext: Context): ViewModel() {

    // 存储对话列表的状态流
    private val _conversationList = MutableStateFlow<List<Conversation>>(emptyList())
    val conversationList: StateFlow<List<Conversation>> = _conversationList
    // 当前对话 ID
    private var _currentConversationId = MutableStateFlow<String?>(null)
    val currentConversationId: StateFlow<String?> = _currentConversationId

    // 对话记录存储目录
    private val conversationsDir = File(appContext.filesDir, "conversations")

    init {
        if (!conversationsDir.exists()) {
            conversationsDir.mkdirs()
        }
        loadConversations() // 加载列表
    }

    fun setCurrentConversationId(id: String) {
        _currentConversationId.value = id
    }

    /**
     * 加载所有对话记录
     */
    fun loadConversations() {
        viewModelScope.launch(Dispatchers.IO) {
            val conversations = mutableListOf<Conversation>()

            conversationsDir.listFiles()?.forEach { folder ->
                val conversationFile = File(folder, "conversation.json")
                if(conversationFile.exists()) {
                    try {
                        val jsonString = conversationFile.readText()
                        val conversation = Gson().fromJson(jsonString, Conversation::class.java)
                        conversations.add(conversation)
                    }catch (e: Exception) {
                        e.printStackTrace()
                    }
                }
            }
            // 按时间戳排序（最新的在前）
            _conversationList.value = conversations.sortedByDescending { it.timestamp }
        }
    }

    /**
     * 创建新对话
     */
    fun createNewConversation(title: String): Conversation {
        val newConversation = Conversation(
            title = title
        )

        saveConversation(newConversation)
        return newConversation
    }

    /**
     * 更新对话标题
     */
    fun updateConversationTitle(id: String, newTitle: String) {
        viewModelScope.launch(Dispatchers.IO) {
            val folder = File(conversationsDir, id)
            val conversationFile = File(folder, "conversation.json")

            if (conversationFile.exists()) {
                try {
                    val jsonString = conversationFile.readText()
                    val conversation = Gson().fromJson(jsonString, Conversation::class.java)
                    conversation.title = newTitle

                    val updatedJsonString = Gson().toJson(conversation)
                    conversationFile.writeText(updatedJsonString)

                    // 更新对话列表
                    val currentList = _conversationList.value.toMutableList()
                    val index = currentList.indexOfFirst { it.id == id }
                    if (index != -1) {
                        currentList[index] = conversation
                        _conversationList.value = currentList.sortedByDescending { it.timestamp }
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }

    /**
     * 更新对话时间戳为当前时间
     */
    fun updateConversationTimestamp(id: String) {
        viewModelScope.launch(Dispatchers.IO) {
            val folder = File(conversationsDir, id)
            val conversationFile = File(folder, "conversation.json")

            if (conversationFile.exists()) {
                try {
                    val jsonString = conversationFile.readText()
                    val conversation = Gson().fromJson(jsonString, Conversation::class.java)
                    conversation.timestamp = System.currentTimeMillis() // 更新时间戳

                    val updatedJsonString = Gson().toJson(conversation)
                    conversationFile.writeText(updatedJsonString)

                    // 更新对话列表
                    val currentList = _conversationList.value.toMutableList()
                    val index = currentList.indexOfFirst { it.id == id }
                    if (index != -1) {
                        currentList[index] = conversation
                        _conversationList.value = currentList.sortedByDescending { it.timestamp }
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }


    /**
     * 删除指定对话
     */
    fun deleteConversation(id: String) {
        viewModelScope.launch(Dispatchers.IO) {
            val folder = File(conversationsDir, id)
            if (folder.exists()) {
                folder.deleteRecursively()
            }

            // 更新对话列表
            val currentList = _conversationList.value.toMutableList()
            currentList.removeAll { it.id == id }
            _conversationList.value = currentList
        }
    }

    /**
     * 保存对话到文件
     */
    private fun saveConversation(conversation: Conversation) {
        viewModelScope.launch(Dispatchers.IO) {
            val folder = File(conversationsDir, conversation.id)
            if (!folder.exists()) {
                folder.mkdirs()
            }

            val conversationFile = File(folder, "conversation.json")
            val jsonString = Gson().toJson(conversation)
            conversationFile.writeText(jsonString)

            // 更新对话列表
            val currentList = _conversationList.value.toMutableList()
            currentList.add(conversation)
            _conversationList.value = currentList.sortedByDescending { it.timestamp }
        }
    }
}