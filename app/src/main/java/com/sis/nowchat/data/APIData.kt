package com.sis.nowchat.data

data class ChatRequest(
    val model: String,
    val messages: List<RequestMessage>,
    val stream: Boolean = true,
    val url: String,
    val api_key: String
)

data class RequestMessage(
    val role: String,
    val content: String
)

data class Choice(
    val message: RequestMessage
)