package com.sis.nowchat.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.Repeat
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.ParagraphStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.sis.nowchat.model.Message


@OptIn(ExperimentalFoundationApi::class)
@Composable
fun AssistantMessage(
    message: Message,
    navController: NavController,
    onLongClick: (Message) -> Unit,
    onCopyClick: () -> Unit,
    isResponding: Boolean,
    regenerate: () -> Unit
) {
    var expandThink by remember { mutableStateOf(true) }
    val context = LocalContext.current

    // 根据 expandThink 动态计算旋转角度
    val rotationAngle by animateFloatAsState(targetValue = if (expandThink) 0f else 180f)
    val clipboardManager = LocalClipboardManager.current    // 获取剪切板

    val hapticFeedback = LocalHapticFeedback.current // 震动

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(
                onClick = {},
                onLongClick = {}
            )
            .combinedClickable(
                onClick = {},
                onLongClick = {
                    onLongClick(message)
                    hapticFeedback.performHapticFeedback(HapticFeedbackType.LongPress)
                }
            )
    ){
        Column(
            modifier = Modifier
                .padding(start = 16.dp, end = 16.dp, bottom = 16.dp, top = if (message.thinkContent.isNotBlank()) 0.dp else 16.dp)
                .fillMaxWidth()
        ) {
            // 是否展示思考布局
            if (message.thinkContent.isNotBlank()){
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "已思考 ${message.thinkTime} 秒",
                        color = MaterialTheme.colorScheme.secondary,
                        style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    )
                    IconButton(onClick = {
                        expandThink = !expandThink
                    }) {
                        Icon(
                            Icons.Outlined.KeyboardArrowDown, modifier = Modifier.rotate(rotationAngle),
                            contentDescription = "展开/收起"
                        )
                    }
                }
                // 思考内容
                AnimatedVisibility(expandThink) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(Color.Gray.copy(alpha = 0.1f))
                    ){
                        Text(
                            text = message.thinkContent.trim(),
                            modifier = Modifier.padding(12.dp),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }
                Spacer(modifier = Modifier.height(16.dp))

            }

            Column(
                modifier = Modifier.fillMaxWidth()
            ) {
                // AI 回复内容
                Box(
                    modifier = Modifier.fillMaxWidth()
                ){
                    MarkdownViewer(message.content)
                }

                //底部操作按钮
                if (!isResponding) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth(),
                        horizontalArrangement = Arrangement.End,
                        verticalAlignment = Alignment.CenterVertically
                    ){
                        // 重新生成按钮
                        IconButton(onClick = {
                            regenerate()
                        },
                            modifier = Modifier.size(36.dp) // 设置按钮大小
                        ) {
                            Icon(
                                Icons.Outlined.Repeat,
                                contentDescription = "修改",
                                modifier = Modifier.size(20.dp) // 设置图标大小
                            )
                        }

                        Spacer(modifier = Modifier.weight(1f))

                        // 修改按钮
                        IconButton(onClick = {
                            navController.navigate("edit_message/${message.id}")
                        },
                            modifier = Modifier.size(36.dp) // 设置按钮大小
                        ) {
                            Icon(
                                Icons.Outlined.Edit,
                                contentDescription = "修改",
                                modifier = Modifier.size(20.dp) // 设置图标大小
                            )
                        }

                        // 复制按钮
                        IconButton(onClick = {
                            val clip = AnnotatedString(message.content, ParagraphStyle())
                            clipboardManager.setText(clip)  // 复制内容到剪切板
                            onCopyClick()
                        },
                            modifier = Modifier.size(36.dp) // 设置按钮大小
                        ) {
                            Icon(
                                Icons.Outlined.ContentCopy,
                                contentDescription = "复制",
                                modifier = Modifier.size(20.dp) // 设置图标大小
                            )
                        }
                    }
                }

            }
        }

    }
}