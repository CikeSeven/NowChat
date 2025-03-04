package com.sis.nowchat

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.sis.nowchat.manager.SettingsManager
import com.sis.nowchat.ui.screen.ChatScreen
import com.sis.nowchat.ui.screen.EditContentScreen
import com.sis.nowchat.ui.theme.NowChatTheme
import com.sis.nowchat.viewmodel.ConversationViewModel
import com.sis.nowchat.viewmodel.ConversationViewModelFactory
import com.sis.nowchat.viewmodel.MessageViewModel
import com.sis.nowchat.viewmodel.MessageViewModelFactory
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch


class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            NowChatTheme {
                SplashScreenContent {
                    MainScreen(this)
                }
            }
        }
    }
}

@Composable
fun MainScreen(
    appContext: MainActivity,
    navController: NavHostController = rememberNavController(),
    settingsManager: SettingsManager = SettingsManager(LocalContext.current),
    messageFactory: MessageViewModelFactory = MessageViewModelFactory(appContext),
    messageViewModel: MessageViewModel = viewModel(factory = messageFactory),   // 获取viewmodel实例
    conversationFactory: ConversationViewModelFactory = ConversationViewModelFactory(appContext),
    conversationViewModel: ConversationViewModel = viewModel(factory = conversationFactory)
){
    val coroutineScope = rememberCoroutineScope()
    // 读取当前主题模式
    var isDarkTheme by remember { mutableStateOf(false) }

    var isInitialLoad by remember { mutableStateOf(true) }

    LaunchedEffect(Unit) {
        settingsManager.isDarkTheme.collect { theme ->
            isDarkTheme = theme
        }
    }

    val chatMessages by messageViewModel.chatMessages.collectAsState()

    NowChatTheme(darkTheme = isDarkTheme){
        NavHost(navController = navController, startDestination = "chat_screen"){
            composable(
                "chat_screen",
                enterTransition = { fadeIn(animationSpec = tween(300)) }, // 进入聊天页面时淡入
                exitTransition = { fadeOut(animationSpec = tween(300)) }  // 离开聊天页面时淡出
            ){
                ChatScreen(
                    messageViewModel = messageViewModel,
                    navController = navController,
                    isDarkTheme = isDarkTheme,
                    onThemeChange = {
                        coroutineScope.launch {
                            isDarkTheme = !isDarkTheme
                            settingsManager.saveThemeMode(isDarkTheme)
                        }
                    },
                    isInitialLoad = isInitialLoad,
                    onInitialized = { isInitialLoad = false },
                    conversationViewModel = conversationViewModel
                )
            }

            composable(
                route = "edit_message/{messageId}",
                arguments = listOf(navArgument("messageId") { type = NavType.StringType }),
                enterTransition = {
                    slideInVertically(animationSpec = tween(400)) { fullHeight -> fullHeight } // 从下往上滑入
                },
                exitTransition = {
                    slideOutVertically(animationSpec = tween(400)) { fullHeight -> -fullHeight } // 从上往下滑出
                },
                popEnterTransition = {
                    slideInVertically(animationSpec = tween(400)) { fullHeight -> -fullHeight } // 返回时从上往下滑入
                },
                popExitTransition = {
                    slideOutVertically(animationSpec = tween(400)) { fullHeight -> fullHeight } // 返回时从下往上滑出
                }
            ){navBackStackEntry ->
                val messageId = navBackStackEntry.arguments?.getString("messageId")
                val message = chatMessages.find { it.id == messageId }
                if (message != null) {
                    EditContentScreen(message = message, navController = navController, messageViewModel = messageViewModel)
                }
            }
        }
    }

}


@Composable
fun SplashScreenContent(onLoadingComplete: @Composable () -> Unit){
    var isLoading by remember { mutableStateOf(true) }

    LaunchedEffect(Unit) {
        delay(300)
        isLoading = false
    }

    if (isLoading) {
        // 加载中的 UI
        Box(
            modifier = Modifier
                .background(MaterialTheme.colorScheme.background)
                .fillMaxSize(),
            contentAlignment = Alignment.Center // 文字居中
        ) {
            Text(
                text = "Now Chat!", // 启动页文字
                fontSize = 32.sp,
                fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.headlineMedium, // 文字样式
                color = Color.Black // 文字颜色
            )
        }
    } else {
        // 加载完成后显示主界面
        onLoadingComplete()
    }
}