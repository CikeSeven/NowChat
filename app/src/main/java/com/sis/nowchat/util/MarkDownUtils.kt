package com.sis.nowchat.util

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import org.commonmark.parser.Parser
import org.commonmark.renderer.html.HtmlRenderer
import org.commonmark.renderer.text.TextContentRenderer

object MarkDownUtils {
    // 创建解析器
    private val parser: Parser = Parser.builder().build()

    /**
     * Markdown文本解析为纯文本
     * @param markdown Markdown文本
     * @return 去除标签后的文本
     */
    fun markdownToPlainText(markdown: String): String {
        // 创建纯文本渲染器
        val renderer = TextContentRenderer.builder().build()

        // 解析 Markdown 并渲染为纯文本
        val document = parser.parse(markdown)
        return renderer.render(document)
    }

    @Composable
    fun markdownToHtml(markdown: String): String{
        val renderer = HtmlRenderer.builder().build()

        val html = remember(markdown) {
            val document = parser.parse(markdown)
            renderer.render(document)
        }
        return html
    }

}