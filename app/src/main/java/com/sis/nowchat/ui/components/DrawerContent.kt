package com.sis.nowchat.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.DarkMode
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.LightMode
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.min
import com.sis.nowchat.model.Conversation

@Composable
fun DrawerContent(
    conversationList: List<Conversation>,
    currentConversation: Conversation?,
    onClickConversation: (Conversation) -> Unit,
    isDarkTheme: Boolean,
    onChangeTheme: () -> Unit,
    newConversationClick: () -> Unit,
    deleteConversation: (Conversation) -> Unit,
    renameConversation: (Conversation, String) -> Unit
) {
    val screenWidth = LocalConfiguration.current.screenWidthDp.dp
    val drawerWidth = min(screenWidth * 0.7f, 300.dp) // 限制侧滑栏宽度为屏幕宽度的 80%，最大 300dp

    ModalDrawerSheet {
        Column (
            modifier = Modifier
                .width(drawerWidth)
                .fillMaxHeight()
                .background(MaterialTheme.colorScheme.background)
        ) {
            Spacer(modifier = Modifier.height(12.dp))
            Text("Now Chat", modifier = Modifier.padding(16.dp), style = MaterialTheme.typography.titleLarge)
            HorizontalDivider(modifier = Modifier.height(0.5.dp))

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        newConversationClick()
                    }
            ){
                Row(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ){
                    Icon(Icons.Outlined.Add, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("开启新对话")
                }
            }


            LazyColumn(
                modifier = Modifier
                    .weight(1f)
            ) {
                items(conversationList){conversation ->
                    ConversationItem(
                        conversation,
                        selected = currentConversation == conversation,
                        onConversationClick = onClickConversation,
                        onDeleteClick = { deleteConversation(conversation) },
                        onRenameClick = { renameConversation(conversation, it) }
                    )
                }
            }


            HorizontalDivider(modifier = Modifier.height(0.5.dp))
            Row(
                modifier = Modifier.fillMaxWidth().padding(8.dp, 8.dp)
            ) {
                IconButton(onClick = {
                    // TODO
                }) {
                    Icon(Icons.Outlined.Settings, contentDescription = "设置")
                }
                Spacer(modifier = Modifier.width(6.dp))
                IconButton(onClick = {
                    //TODO
                }) {
                    Icon(Icons.Outlined.Info, contentDescription = "关于")
                }
                Spacer(modifier = Modifier.width(6.dp))
                IconButton(onClick = {
                    onChangeTheme()
                }) {
                    Icon(if(isDarkTheme) Icons.Outlined.LightMode else Icons.Outlined.DarkMode, contentDescription = "切换主题")
                }
            }
        }
    }
}