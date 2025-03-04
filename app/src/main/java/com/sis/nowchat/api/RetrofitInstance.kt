package com.sis.nowchat.api

import com.sis.nowchat.data.ChatRequest
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory

object RetrofitInstance {

    fun createApi(chatRequest: ChatRequest): ChatApiService {
        // 创建 OkHttpClient 并添加拦截器
        val client = OkHttpClient.Builder()
            .addInterceptor(createAuthInterceptor(chatRequest.api_key))
            .build()

        return Retrofit.Builder()
            .baseUrl(chatRequest.url)
            .client(client)
            .addConverterFactory(GsonConverterFactory.create()) // 添加 Gson 转换器
            .build()
            .create(ChatApiService::class.java)
    }

    /**
     * 创建认证头拦截器
     */
    private fun createAuthInterceptor(apiKey: String): Interceptor {
        return Interceptor { chain ->
            val originalRequest = chain.request()
            val authenticatedRequest = originalRequest.newBuilder()
                .header("Authorization", "Bearer $apiKey") // 添加认证头
                .build()
            chain.proceed(authenticatedRequest) // 继续请求链
        }
    }
}