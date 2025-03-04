package com.sis.nowchat.ui.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import com.sis.nowchat.model.Message
import kotlin.math.roundToInt

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun UserMessage(
    message: Message,
    onLongClick: (Message) -> Unit
){

    var showMenu by remember { mutableStateOf(false) } // 长按菜单
    var menuOffset by remember { mutableStateOf(Offset.Zero) }

    val hapticFeedback = LocalHapticFeedback.current

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 48.dp, end = 16.dp, bottom = 16.dp, top = 16.dp),
        horizontalArrangement = Arrangement.End
    ){
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(topStart = 12.dp, topEnd = 4.dp, bottomStart = 12.dp, bottomEnd = 12.dp)) // 圆角
                .background(color = MaterialTheme.colorScheme.primaryContainer)
                .combinedClickable(
                    onClick = {},
                    onLongClick = {
                        onLongClick(message)
                        hapticFeedback.performHapticFeedback(HapticFeedbackType.LongPress)
                    }
                )
        ) {
            Text(
                text = message.content,
                modifier = Modifier
                    .padding(12.dp)
            )

            if(showMenu) {
                Popup(
                    offset = IntOffset(menuOffset.x.roundToInt(), menuOffset.y.roundToInt()),
                    onDismissRequest = { showMenu = false }
                ) {
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
                                // TODO
                                showMenu = false
                            },
                            leadingIcon = { Icon(Icons.Outlined.Edit, contentDescription = null) }
                        )

                        HorizontalDivider()
                        DropdownMenuItem(
                            text = { Text("删除", color = MaterialTheme.colorScheme.error) },
                            onClick = {
                                // TODO
                                showMenu = false
                            },
                            leadingIcon = { Icon(Icons.Outlined.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error) }
                        )

                    }
                }
            }
        }
    }
}