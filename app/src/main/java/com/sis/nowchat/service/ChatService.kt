package com.sis.nowchat.service

import android.util.Log
import com.google.gson.Gson
import com.sis.nowchat.api.RetrofitInstance
import com.sis.nowchat.data.ChatRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import okhttp3.Dispatcher
import okhttp3.ResponseBody
import java.io.BufferedReader
import java.io.InputStreamReader

data class StreamChunk(
    val choices: List<Choice>
)

data class Choice(
    val delta: Delta
)

data class Delta(
    val content: String? = null,
    val reasoning_content: String? = null
)



class ChatService {
    private val gson = Gson()

    // 标志变量，用于控制是否取消流式处理
    private var shouldCancel: Boolean = false

    suspend fun sendMessageStream(chatRequest: ChatRequest): Flow<String> {
        return flow {
            val chatApiService = RetrofitInstance.createApi(chatRequest)

            val responseBody : ResponseBody = chatApiService.sendMessageStream(url = chatRequest.url, chatRequest = chatRequest)

            val reader = BufferedReader(InputStreamReader(responseBody.byteStream()))

            var line: String?

            while (reader.readLine().also { line = it } != null) {

                if (shouldCancel) {
                    // 如果需要取消，则停止处理
                    println("Stream cancelled by user")
                    break
                }

                if (line?.startsWith("data:") == true) {
                    val jsonString = line?.substringAfter("data:")
                    when {
                        jsonString == "[DONE]" -> {
                            // 结束循环
                            println("finished")
                            break
                        }
                        jsonString.isNullOrBlank() -> {
                            // 跳过空行
                            continue
                        }
                        else -> {
                            try {
                                // 尝试解析为对象
                                val chunk = gson.fromJson(jsonString, StreamChunk::class.java)
                                chunk.choices.forEach { choice ->
                                    if (choice.delta.reasoning_content != null) {
                                        // 如果有思考内容
                                        emit("[Reasoning]${choice.delta.reasoning_content}")
                                    }else {
                                        choice.delta.content?.let { emit(it) }
                                    }
                                }
                            }catch (e: Exception) {
                                Log.e("parsing error","json: $jsonString , error: $e")
                            }
                        }
                    }
                }
            }
        }.flowOn(Dispatchers.IO)
    }

    fun cancelStream() {
        shouldCancel = true
        println("执行cancelStream() 方法")
    }
}
