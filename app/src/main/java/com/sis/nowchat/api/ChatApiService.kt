package com.sis.nowchat.api

import com.sis.nowchat.data.ChatRequest
import okhttp3.ResponseBody
import retrofit2.http.Body
import retrofit2.http.Headers
import retrofit2.http.POST
import retrofit2.http.Streaming
import retrofit2.http.Url

interface ChatApiService {
    @Headers("Content-Type: application/json")
    @Streaming
    @POST
    suspend fun sendMessageStream(
        @Url url: String,
        @Body chatRequest: ChatRequest
    ): ResponseBody
}