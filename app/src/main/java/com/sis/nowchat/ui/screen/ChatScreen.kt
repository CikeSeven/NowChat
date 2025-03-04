package com.sis.nowchat.ui.screen

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberDrawerState
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
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.substring
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.sis.nowchat.data.APIProvider
import com.sis.nowchat.data.MessageRole
import com.sis.nowchat.model.APIModel
import com.sis.nowchat.model.Conversation
import com.sis.nowchat.model.Message
import com.sis.nowchat.ui.components.AssistantMessage
import com.sis.nowchat.ui.components.BottomInput
import com.sis.nowchat.ui.components.BottomSheet
import com.sis.nowchat.ui.components.DrawerContent
import com.sis.nowchat.ui.components.ProviderDialog
import com.sis.nowchat.ui.components.UserMessage
import com.sis.nowchat.util.APIStorage
import com.sis.nowchat.viewmodel.ConversationViewModel
import com.sis.nowchat.viewmodel.MessageViewModel
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(
    navController: NavController,
    messageViewModel: MessageViewModel,
    isDarkTheme: Boolean,
    onThemeChange: () -> Unit,
    isInitialLoad: Boolean,
    onInitialized: () -> Unit,
    conversationViewModel: ConversationViewModel
) {
    val context = LocalContext.current

    //apiStore工具
    val apiStore = remember { APIStorage(context) }

    val scope = rememberCoroutineScope()
    val drawerState = rememberDrawerState(DrawerValue.Closed)
    var showMenu by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()

    var showSheet by remember { mutableStateOf(false) } // 是否展示底栏
    var content by remember { mutableStateOf("") }

    val conversationList by conversationViewModel.conversationList.collectAsState()

    var currentConversation by remember { mutableStateOf<Conversation?>(null) }

    LaunchedEffect(conversationList) {
        currentConversation = if (conversationList.isNotEmpty()) {
            conversationList.maxByOrNull { it.timestamp }
        }else {
            null
        }
    }

    var choiceMessage by remember { mutableStateOf<Message?>(null) } // 选择的消息

    val snackbarHostState = remember { SnackbarHostState() } // 弹出提示

    var showAPIDialog by remember { mutableStateOf(false) } // 选择API弹窗

    var apiList by remember { mutableStateOf(mutableListOf<APIModel>()) }

    var apiModel: APIModel? by remember { mutableStateOf(null) } // 当前使用的API

    // 获取当前选择的模型和模型列表
    val currentModel = apiModel?.getCurrentModel() ?: ""
    val modelList = apiModel?.getValidModels() ?: emptyList()

    val chatMessages by messageViewModel.chatMessages.collectAsState()

    // 监听是否正在回答问题
    val isResponding by messageViewModel.isResponding.collectAsState()

    LaunchedEffect (Unit) {
        apiList = apiStore.getAllAPIs().toMutableList()
        println(apiList)
    }

    LaunchedEffect(Unit) {
        // 加载对话记录
        if (currentConversation != null) {
            messageViewModel.loadMessagesForConversation(currentConversation!!.id)
        }
    }

    LaunchedEffect(Unit) {
        // 读取当前选择的 API ID 和模型
        val savedApiId = apiStore.getCurrentSelection()

        // 根据保存的 API ID 加载对应的 API 数据
        if (savedApiId != null) {
            println("读取到api id:$savedApiId")
            val loadedApi = apiStore.getAPI(savedApiId)
            if (loadedApi != null) {
                apiModel = loadedApi
            }
        }
    }

    if (drawerState.isOpen){
        BackHandler {
            scope.launch {
                drawerState.close()
            }
        }
    }

    LaunchedEffect(isInitialLoad) {
        if (isInitialLoad){
            if (chatMessages.size > 1) {
                listState.scrollToItem(chatMessages.size - 1)
            }
            onInitialized()
        }
    }

    // 如果用户切换了 API 或模型，更新状态
    suspend fun updateAPI(newApiModel: APIModel?) {
        apiModel = newApiModel
        apiStore.saveAPI(apiModel!!)
        // 更新 API 列表
        apiList = apiList.map { model ->
            if (model.id == newApiModel?.id) newApiModel else model
        }.toMutableList()
    }

    ModalNavigationDrawer(
    drawerState = drawerState,
        drawerContent = {
            DrawerContent(
                conversationList = conversationList,
                currentConversation = currentConversation,
                onClickConversation = {
                    if (!isResponding) {
                        if (currentConversation == null) {
                            currentConversation = it
                            messageViewModel.loadMessagesForConversation(it.id)
                            scope.launch {
                                drawerState.close()
                                if (chatMessages.isNotEmpty()) {
                                    listState.animateScrollToItem(chatMessages.size - 1)
                                }
                            }
                        }
                        else if (currentConversation!!.id != it.id) {
                            currentConversation = it
                            scope.launch {
                                messageViewModel.loadMessagesForConversation(it.id)
                                drawerState.close()
                                if (chatMessages.isNotEmpty()) {
                                    listState.animateScrollToItem(chatMessages.size - 1)
                                }
                            }
                        }
                    }
                },
                onChangeTheme = onThemeChange,
                isDarkTheme = isDarkTheme,
                newConversationClick = {
                    if (!isResponding) {
                        currentConversation = null
                        scope.launch {
                            messageViewModel.loadMessagesForConversation(null)
                            drawerState.close()
                        }
                    }
                },
                deleteConversation = {
                    if (isResponding) {
                        if (currentConversation!!.id != it.id) {
                            conversationViewModel.deleteConversation(it.id)
                        }
                    }else {
                        conversationViewModel.deleteConversation(it.id)
                        if (currentConversation?.id == it.id){
                            currentConversation = null
                            messageViewModel.loadMessagesForConversation(null)
                        }
                    }
                },
                renameConversation = { conv, newTitle ->
                    conversationViewModel.updateConversationTitle(conv.id, newTitle)
                }
            )
        }
    ) {
        Scaffold(
            snackbarHost = {
                // 使用 Box 调整 Snackbar 位置
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(top = 96.dp), // 调整距离顶部的距离
                    contentAlignment = Alignment.TopCenter // 设置为顶部居中
                ) {
                    SnackbarHost(hostState = snackbarHostState)
                }
            },
            topBar ={
                TopAppBar(
                    title = {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 12.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ){
                            Text(
                                text = currentConversation?.title ?: "新对话",
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Bold)
                            )
                            Column(
                                horizontalAlignment = Alignment.CenterHorizontally,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .pointerInput(Unit) {
                                        detectTapGestures(
                                            onTap = { showAPIDialog = true }
                                        )
                                    }
                            ){
                                Text(
                                    modifier = Modifier.padding(8.dp),
                                    text = apiModel?.name ?: "点击选择API",
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    color = MaterialTheme.colorScheme.secondary,
                                    style = MaterialTheme.typography.titleSmall
                                )
                            }
                        }
                    },
                    navigationIcon = {
                        IconButton(onClick = {
                            scope.launch {
                                drawerState.open()
                            }
                        }
                        ) {
                            Icon(Icons.Default.Menu, contentDescription = "菜单")
                        }
                    },
                    actions = {
                        IconButton(onClick = { showMenu = !showMenu}) {
                            Icon(Icons.Outlined.MoreVert, contentDescription = "菜单")
                        }
                        AnimatedVisibility(
                            visible = showMenu,
                            enter = slideInVertically(animationSpec = tween(durationMillis = 300)) + fadeIn(),
                            exit = slideOutVertically(animationSpec = tween(durationMillis = 300)) + fadeOut()
                        ) {
                            DropdownMenu(
                                offset = DpOffset((-16).dp, 16.dp),
                                expanded = showMenu,
                                onDismissRequest = { showMenu = false }
                            ) {
                                DropdownMenuItem(
                                    leadingIcon = { Icon(Icons.Rounded.ArrowDownward, contentDescription = null) },
                                    text = { Text("回到底部") },
                                    onClick = {
                                        scope.launch {
                                            if (chatMessages.isNotEmpty()) {
                                                listState.animateScrollToItem(chatMessages.size - 1)
                                            }
                                        }
                                        showMenu = false
                                    }
                                )
                            }
                        }


                    }
                )
            }
        ){innerPadding ->
            Column(
                modifier = Modifier.padding(innerPadding)
            ) {
                LazyColumn(
                    state = listState,
                    modifier = Modifier
                        .weight(1f)
                ) {
                    items(chatMessages) {message ->
                        if (message.role == MessageRole.USER){
                            UserMessage(
                                message,
                                onLongClick = {
                                    choiceMessage = it
                                    showSheet = true
                                }
                            )
                        }else if (message.role == MessageRole.ASSISTANT){
                            AssistantMessage(
                                message = message,
                                navController = navController,
                                onLongClick = {
                                    if (!isResponding) {
                                        choiceMessage = it
                                        showSheet = true
                                    }
                                },
                                onCopyClick = {
                                    scope.launch {
                                        snackbarHostState.showSnackbar(
                                            "复制成功",
                                            duration = SnackbarDuration.Short
                                        )
                                    }
                                },
                                isResponding = isResponding,
                                regenerate = {
                                    if (!isResponding && apiModel != null) {
                                        messageViewModel.sendMessage(apiModel!!, regenerate = true, conversationId = currentConversation!!.id)
                                    }
                                }
                            )
                        }
                    }
                }

                // 底部输入框组件
                BottomInput(
                    content = content,
                    onValueChange = { content = it },
                    modelList = modelList ,
                    currentModel = currentModel,
                    selectedModel = { scope.launch {
                        updateAPI(apiModel!!.copy(selectedModel = it))
                    } },
                    onSendClick = {
                        if (isResponding) {
                            println("点击停止按钮")
                            messageViewModel.disconnect()
                        }else {
                            if (currentConversation == null) {
                                currentConversation = conversationViewModel.createNewConversation(if (content.length > 30) content.substring(0, 30) else content)
                            }else {
                                conversationViewModel.updateConversationTimestamp(currentConversation!!.id)
                            }
                            messageViewModel.addMessage(Message(role = MessageRole.USER, content = content))
                            content = ""
                            scope.launch {
                                listState.animateScrollToItem(chatMessages.size - 1)
                                if (apiModel != null) {
                                    messageViewModel.sendMessage(apiModel!!, conversationId = currentConversation!!.id)
                                }
                            }
                        }
                    },
                    isResponding = isResponding
                )
            }
        }
    }

    if (showAPIDialog) {
        ProviderDialog(
            onDismiss = {
                showAPIDialog = false
                if (apiModel != null) {
                    apiModel = apiList.find { it.name == apiModel!!.name }
                    scope.launch {
                        apiStore.saveCurrentSelection(apiModel!!.id)
                    }
                }
            },
            apiList = apiList,
            apiModel = apiModel,
            changed = run {
                apiModel?.equals(apiList.find { it.name == apiModel?.name }) != true
            },
            onSelectAPI = { apiModel = it },
            onSave = {
                scope.launch {
                    apiStore.saveAPI(apiModel!!)
                    apiList = apiStore.getAllAPIs().toMutableList()
                }
            },
            updateAPI = { newModel ->
                apiModel = newModel
            },
            onCreate = {
                scope.launch {
                    apiStore.saveAPI(it)
                    apiList = apiStore.getAllAPIs().toMutableList()
                }
                apiModel = it
            },
            onDelete = {
                scope.launch {
                    apiStore.deleteAPI(apiModel!!.id)
                    apiList = apiStore.getAllAPIs().toMutableList()
                    apiModel = null
                }
            }
        )
    }

    // 弹出底部消息操作板
    if (choiceMessage != null) {
        BottomSheet(
            showSheet = showSheet,
            message = choiceMessage!!,
            onDismiss = {text ->
                showSheet = false
                if (text.isNotBlank()){
                    scope.launch {
                        snackbarHostState.showSnackbar(
                            text,
                            duration = SnackbarDuration.Short
                        )
                    }
                }
            },
            onEditClick = {
                showMenu = false
                navController.navigate("edit_message/${choiceMessage!!.id}")
            },
            deleteMessage = { messageViewModel.deleteMessage(choiceMessage!!) },
            deleteMessageAfter = { messageViewModel.deleteMessageAfter(choiceMessage!!) }
        )
    }


}