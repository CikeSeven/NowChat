package com.sis.nowchat.data

enum class APIProvider {
    OPENAI_COM, // OPENAI 兼容模式
    OPENAI,
    DEEPSEEK,
    CLAUDE,
    GOOGLE_GEMINI,
    OLLAMA;

    fun toValue(): String = when (this) {
        OPENAI_COM -> "OpenAI 兼容"
        OPENAI -> "OpenAI"
        CLAUDE -> "Claude"
        GOOGLE_GEMINI -> "Google Gemini"
        DEEPSEEK -> "DeepSeek"
        OLLAMA -> "Ollama"
    }

}