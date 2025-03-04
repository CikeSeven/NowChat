package com.sis.nowchat.ui.components

import android.content.Context
import android.os.Vibrator
import android.os.VibratorManager
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.DriveFileRenameOutline
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.Popup
import com.sis.nowchat.model.Conversation

@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable
fun ConversationItem(
    conversation: Conversation,
    selected: Boolean,
    onConversationClick: (Conversation) -> Unit,
    onDeleteClick: () -> Unit,
    onRenameClick: (String) -> Unit
) {
    val context = LocalContext.current
    var showMenu by remember { mutableStateOf(false) } // 长按菜单
    var showDeleteDialog by remember { mutableStateOf(false) } // 删除弹窗
    var showRenameDialog by remember { mutableStateOf(false) } // 重命名弹窗
    var newTitle by remember { mutableStateOf("") }
    val hapticFeedback = LocalHapticFeedback.current

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(if (selected) MaterialTheme.colorScheme.surfaceVariant else MaterialTheme.colorScheme.background)
            .combinedClickable(
                onClick = {
                    onConversationClick(conversation)
                },
                onLongClick = {
                    hapticFeedback.performHapticFeedback(HapticFeedbackType.LongPress)
                    showMenu = true
                }
            )
    ) {
        Text(
            text = conversation.title,
            color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier
                .padding(16.dp, 12.dp),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )

        //重命名弹窗
        if (showRenameDialog) {
            Dialog(onDismissRequest = { showRenameDialog = false }) {
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .wrapContentHeight(),
                    shape = MaterialTheme.shapes.medium,
                    tonalElevation = 6.dp
                ) {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(16.dp)
                    ) {
                        Text("重命名")
                        Spacer(modifier = Modifier.height(16.dp))
                        OutlinedTextField(
                            value = newTitle,
                            onValueChange = { newTitle = it },
                            maxLines = 1,
                            label = { Text("新标题") }
                        )
                        Spacer(modifier = Modifier.height(16.dp))
                        Row(
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            TextButton(onClick = {
                                showRenameDialog = false
                                newTitle = ""
                            }) { Text("取消") }
                            Spacer(modifier = Modifier.weight(1f))

                            TextButton(onClick = {
                                onRenameClick(newTitle.trim())
                                newTitle = ""
                                showRenameDialog = false
                            },
                                enabled = newTitle.trim().isNotBlank()
                            ) { Text("重命名") }
                        }
                    }
                }
            }
        }

        // 展示删除确认弹窗
        if (showDeleteDialog) {
            AlertDialog(
                onDismissRequest = { showDeleteDialog = false },
                title = { Text("确认删除")},
                text ={ Text("确定要永久删除当前对话吗？")},
                confirmButton = {
                    TextButton(onClick = {
                        onDeleteClick()
                        showDeleteDialog = false
                    }) {
                        Text("确认", color = MaterialTheme.colorScheme.error)
                    }
                },
                dismissButton = {
                    TextButton(onClick = { showDeleteDialog = false }) {
                        Text("取消")
                    }
                }
            )
        }

        if (showMenu){
            BackHandler {
                showMenu = false
            }
            Popup(
                offset = IntOffset(0, 160),
                alignment = Alignment.Center,
                onDismissRequest = { showMenu = false }
            ){
                Column(
                    modifier = Modifier
                        .clip(RoundedCornerShape(16.dp))
                        .width(200.dp)
                        .padding(16.dp)
                        .shadow(elevation = 8.dp, shape = RoundedCornerShape(16.dp))
                        .background(MaterialTheme.colorScheme.surface),
                ) {
                    DropdownMenuItem(
                        text = { Text("重命名") },
                        onClick = {
                            showRenameDialog = true
                            newTitle = conversation.title
                            showMenu = false
                        },
                        leadingIcon = { Icon(Icons.Outlined.DriveFileRenameOutline, contentDescription = null) }
                    )

                    HorizontalDivider()
                    DropdownMenuItem(
                        text = { Text("删除", color = MaterialTheme.colorScheme.error) },
                        onClick = {
                            showDeleteDialog = true
                            showMenu = false
                        },
                        leadingIcon = { Icon(Icons.Outlined.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error) }
                    )

                }
            }
        }



    }

}