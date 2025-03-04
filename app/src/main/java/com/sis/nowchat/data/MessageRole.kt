package com.sis.nowchat.data

enum class MessageRole {
    USER, //用户
    ASSISTANT, //AI
    SYSTEM; //系统设定

    fun toValue(): String = when (this) {
        USER -> "user"
        ASSISTANT -> "assistant"
        SYSTEM -> "system"
    }

    companion object {
        fun fromValue(value: String): MessageRole? = when (value.lowercase()) {
            "user" -> USER
            "assistant" -> ASSISTANT
            "system" -> SYSTEM
            else -> null
        }
    }
}