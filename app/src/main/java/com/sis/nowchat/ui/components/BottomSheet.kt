package com.sis.nowchat.ui.components

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.DeleteForever
import androidx.compose.material.icons.outlined.DeleteSweep
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.SheetValue
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.ParagraphStyle
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.substring
import androidx.compose.ui.unit.dp
import com.sis.nowchat.data.MessageRole
import com.sis.nowchat.model.Message
import com.sis.nowchat.util.MarkDownUtils
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BottomSheet(
    showSheet: Boolean,
    message: Message,
    onDismiss: (String) -> Unit,
    onEditClick: () -> Unit,
    deleteMessage: () -> Unit,
    deleteMessageAfter: () -> Unit
) {
    val clipboardManager = LocalClipboardManager.current    // 获取手机剪切板
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false) // 展开状态管理

    var isFullyExpanded by remember { mutableStateOf(false) }
    val context = LocalContext.current

    // 监听 Bottom Sheet 的状态变化
    LaunchedEffect(sheetState.currentValue) {
        isFullyExpanded = sheetState.currentValue == SheetValue.Expanded
    }
    var textFieldValue by remember {
        mutableStateOf(TextFieldValue(MarkDownUtils.markdownToPlainText(message.content)))
    }
    LaunchedEffect(message) {
        val newText = MarkDownUtils.markdownToPlainText(message.content)
        textFieldValue = TextFieldValue(newText, TextRange(0, 0)) // 重置选中范围
    }

    var selectedText by remember { mutableStateOf("") }

    if (showSheet){
        ModalBottomSheet(
            onDismissRequest = { onDismiss("") },
            sheetState = sheetState
        ) {
            Column(
                modifier = Modifier
                    .padding(horizontal = 16.dp)
            ) {
                // 编辑按钮
                NavigationDrawerItem(
                    modifier = Modifier.height(52.dp),
                    selected = false,
                    label = { Text("编辑消息") },
                    icon = { Icon(Icons.Outlined.Edit, contentDescription = null) },
                    onClick = {
                        onEditClick()
                        onDismiss("")
                    },
                )
                // 复制内容按钮
                NavigationDrawerItem(
                    modifier = Modifier.height(52.dp),
                    selected = false,
                    label = { Text(if (selectedText.isNotBlank()) "复制选择内容" else "复制全文") },
                    icon = { Icon(Icons.Outlined.ContentCopy, contentDescription = null) },
                    onClick = {
                        if (selectedText.isNotBlank()){
                            val clip = AnnotatedString(selectedText, ParagraphStyle())
                            clipboardManager.setText(clip)  // 复制选择内容到剪切板
                        }else {
                            val clip = AnnotatedString(textFieldValue.text, ParagraphStyle())
                            clipboardManager.setText(clip)  // 复制内容到剪切板
                            onDismiss("复制成功")
                        }
                    },
                )

                AnimatedVisibility(
                    !isFullyExpanded || message.role == MessageRole.USER
                ) {
                    Column {
                        // 分享按钮
                        NavigationDrawerItem(
                            modifier = Modifier.height(52.dp),
                            selected = false,
                            label = { Text(if (selectedText.isNotBlank()) "分享选择内容" else "分享内容") },
                            icon = { Icon(Icons.Outlined.Share, contentDescription = null) },
                            onClick = {
                                if (selectedText.isNotBlank()){
                                    shareText(context, selectedText)
                                }else {
                                    shareText(context, textFieldValue.text)
                                    onDismiss("")
                                }
                            },
                        )
                        // 删除单条消息按钮
                        NavigationDrawerItem(
                            modifier = Modifier.height(52.dp),
                            selected = false,
                            label = { Text("删除这条消息") },
                            icon = { Icon(Icons.Outlined.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error) },
                            onClick = {
                                deleteMessage()
                                onDismiss("")
                            },
                        )
                        // 批量删除消息按钮
                        NavigationDrawerItem(
                            modifier = Modifier.height(52.dp),
                            selected = false,
                            label = { Text("删除这条及其以后的消息") },
                            icon = { Icon(Icons.Outlined.DeleteForever, contentDescription = null, tint = MaterialTheme.colorScheme.error) },
                            onClick = {
                                deleteMessageAfter()
                                onDismiss("")
                            },
                        )
                    }

                }

                // 选择文本
                if(message.role == MessageRole.ASSISTANT){
                    HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp))
                    Column(
                        modifier = Modifier.weight(1f).padding(16.dp)
                    ){
                        Column {

                            BasicTextField(
                                value = textFieldValue,
                                onValueChange = { newTextFieldValue ->
                                    textFieldValue = newTextFieldValue
                                    val selection = newTextFieldValue.selection
                                    if (selection.start in 0..newTextFieldValue.text.length &&
                                        selection.end in 0..newTextFieldValue.text.length &&
                                        selection.start <= selection.end
                                    ) {
                                        selectedText = newTextFieldValue.text.substring(selection.start, selection.end)
                                    } else {
                                        selectedText = ""
                                    }
                                },
                                readOnly = true,
                                modifier = Modifier.fillMaxWidth(),
                                textStyle = MaterialTheme.typography.bodyMedium,
                            )
                        }
                    }
                }
            }
        }
    }

}

// 将分享逻辑封装为扩展函数
private fun shareText(context: Context, text: String) {
    val sendIntent = Intent().apply {
        action = Intent.ACTION_SEND
        putExtra(Intent.EXTRA_TEXT, text)
        type = "text/plain"
    }

    val shareIntent = Intent.createChooser(sendIntent, "分享到")
    if (sendIntent.resolveActivity(context.packageManager) != null) {
        context.startActivity(shareIntent)
    } else {
        Log.e("分享失败","未找到可分享应用")
    }
}