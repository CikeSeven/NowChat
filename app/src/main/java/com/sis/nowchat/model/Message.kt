package com.sis.nowchat.model

import android.os.Parcelable
import com.google.gson.Gson
import com.sis.nowchat.data.MessageRole
import com.sis.nowchat.data.RequestMessage
import kotlinx.parcelize.Parcelize
import java.io.File
import java.util.UUID

@Parcelize
data class Message(
    val id: String = UUID.randomUUID().toString(),
    val role: MessageRole,
    var content: String,
    val thinkContent: String = "",
    val thinkTime: Float = 0f
) :  Parcelable

fun Message.toRequestMessage(): RequestMessage {
    return RequestMessage(
        role = this.role.toValue(), // 将 MessageRole 转换为 String
        content = this.content
    )
}