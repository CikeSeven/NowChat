package com.sis.nowchat.ui.components

import android.graphics.Typeface
import android.text.Spanned
import android.text.style.StyleSpan
import android.text.style.UnderlineSpan
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.core.text.HtmlCompat
import com.sis.nowchat.util.MarkDownUtils

@Composable
fun MarkdownViewer(markdown: String, modifier: Modifier = Modifier) {
    val html = MarkDownUtils.markdownToHtml(markdown)
    MaterialTheme {
        HtmlText(html)
    }
}

@Composable
fun HtmlText(htmlContent: String) {
    val spanned = HtmlCompat.fromHtml(htmlContent, HtmlCompat.FROM_HTML_MODE_LEGACY)
    val annotatedString = spanned.toAnnotatedString()
    Text(text = annotatedString)
}

fun Spanned.toAnnotatedString(): AnnotatedString {
    return buildAnnotatedString {
        append(this@toAnnotatedString.toString())
        this@toAnnotatedString.getSpans(0, length, Any::class.java).forEach { span ->
            val start = getSpanStart(span)
            val end = getSpanEnd(span)
            when (span) {
                is StyleSpan -> {
                    when (span.style) {
                        Typeface.BOLD -> addStyle(SpanStyle(fontWeight = FontWeight.Bold), start, end)
                        Typeface.ITALIC -> addStyle(SpanStyle(fontStyle = FontStyle.Italic), start, end)
                    }
                }
                is UnderlineSpan -> {
                    addStyle(SpanStyle(textDecoration = TextDecoration.Underline), start, end)
                }
                // 处理其他 Span 类型
            }
        }
    }
}