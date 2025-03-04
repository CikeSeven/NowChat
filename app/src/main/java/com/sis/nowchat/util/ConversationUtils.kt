package com.sis.nowchat.util

import com.google.gson.Gson
import com.sis.nowchat.model.Conversation
import com.sis.nowchat.model.Message
import java.io.File

object ConversationUtils {

    private val gson = Gson()
    fun saveMessagesToJson(messageList: List<Message>, conversation: Conversation) {
        val jsonString =gson.toJson(messageList)
        // TODO
    }
}