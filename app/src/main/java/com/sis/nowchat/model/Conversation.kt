package com.sis.nowchat.model

import java.util.UUID

data class Conversation(
    val id: String = UUID.randomUUID().toString(), // 自动生成唯一 ID
    var title: String,
    var timestamp: Long = System.currentTimeMillis()
)
