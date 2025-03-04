package com.sis.nowchat.ui.screen

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavController
import com.sis.nowchat.model.Message
import com.sis.nowchat.viewmodel.MessageViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditContentScreen(
    navController: NavController,
    message: Message,
    messageViewModel: MessageViewModel = viewModel()
) {
    var content by remember { mutableStateOf(message.content) }

    var rota by remember { mutableStateOf(false) }

    LaunchedEffect(key1 = message) {
        rota = true
    }
    // 动态计算旋转角度
    val rotationAngle by animateFloatAsState(
        targetValue = if (rota) 270f else 0f,
        animationSpec = tween(durationMillis = 600) // 设置动画持续时间为 300 毫秒
    )

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("") },
                navigationIcon = {
                    // 关闭按钮
                    IconButton(onClick = {
                        rota = false
                        navController.popBackStack()
                    }
                    ) { Icon(Icons.Outlined.Close, modifier = Modifier.rotate(rotationAngle), contentDescription = "关闭") }
                },
                actions = {
                    // 保存按钮
                    IconButton(onClick = {
                        message.content = content
                        rota = false
                        navController.popBackStack()
                    }) { Icon(Icons.Outlined.Check, contentDescription = "保存") }
                }
            )
        }
    ) {innerPadding ->
        Column(
            modifier = Modifier.padding(innerPadding)
        ) {
            BasicTextField(
                value = content,
                onValueChange = { content = it },
                textStyle = TextStyle(fontSize = 16.sp),
                modifier = Modifier
                    .fillMaxWidth()
                    .imePadding()
                    .weight(1f)
                    .padding(16.dp)
            )

            Row(
                modifier = Modifier
                    .fillMaxWidth()
            ) {  }
        }
    }
}