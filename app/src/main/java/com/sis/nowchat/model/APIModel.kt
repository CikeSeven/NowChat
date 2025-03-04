package com.sis.nowchat.model

import com.sis.nowchat.data.APIProvider
import java.util.UUID

data class APIModel(
    val id: String = UUID.randomUUID().toString(), // 自动生成唯一 ID
    val name: String, // 名称
    val apiProvider: APIProvider?,
    val apiUrl: String, // API URL
    val apiPath: String, // API 路径（如 /chat/completions）
    val apiKey: String = "", // API 密钥
    val models: List<String>, // 模型列表
    val selectedModel: String? = "",
    val contextMessages: Int, // 上下文消息数
    val temperature: Double, // temperature参数
    val top_p: Double
){
    // 获取有效的模型列表
    fun getValidModels(): List<String> {
        return models.filter { it.isNotEmpty() }
    }

    // 获取当前选择的模型，如果无效则返回第一个模型或空字符串
    fun getCurrentModel(): String {
        return if (selectedModel != null && models.contains(selectedModel)) {
            selectedModel
        } else {
            models.firstOrNull() ?: ""
        }
    }
}
