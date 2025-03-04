package com.sis.nowchat.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material3.ButtonColors
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import com.sis.nowchat.data.APIProvider
import com.sis.nowchat.model.APIModel
import kotlin.math.roundToInt

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ProviderDialog(
    apiModel: APIModel? = null,
    onDismiss: () -> Unit,
    changed: Boolean,
    onSave: () -> Unit,
    onCreate: (APIModel) -> Unit,
    apiList: List<APIModel> = emptyList(),
    onSelectAPI: (APIModel) -> Unit,
    updateAPI: (APIModel) -> Unit,
    onDelete: () -> Unit
){

    var isProviderDropdownExpanded by remember { mutableStateOf(false) } // 控制API提供方菜单显示
    var isAPIDropdownExpanded by remember { mutableStateOf(false) } // 控制API提供方菜单显示
    var onCreationAPI by remember { mutableStateOf(false) } // 正在创建中的API

    // 创建中的API
    val newAPI by remember { mutableStateOf(APIModel(
        name = "",
        apiProvider = null,
        apiUrl = "",
        apiPath = "/chat/completions",
        apiKey = "",
        models = emptyList(),
        contextMessages = 20,
        temperature = 1.0,
        top_p = 1.0
    )) }
    // 创建中的API
    var creatingAPI by remember { mutableStateOf(newAPI) }

    // API 提供方列表
    val apiProviderList = listOf(
        APIProvider.OPENAI_COM,
        APIProvider.OPENAI,
        APIProvider.DEEPSEEK,
        APIProvider.CLAUDE,
        APIProvider.GOOGLE_GEMINI,
        APIProvider.OLLAMA
    )

    // 判断当前是新建还是选择的api
    val currentAPI = if (onCreationAPI || apiModel == null) creatingAPI else apiModel

    val scrollState = rememberScrollState()

    println("${ apiModel?.equals(apiList.find { it.name == apiModel.name }) }")

    Dialog(onDismissRequest = {}) {
        Surface(
            shape = MaterialTheme.shapes.medium,
            color = MaterialTheme.colorScheme.surface,
            modifier = Modifier
                .verticalScroll(scrollState)
                .fillMaxWidth()
                .wrapContentHeight()
        ) {
            Column {
                Column(
                    modifier = Modifier
                        .padding(start = 16.dp, end = 16.dp, top = 16.dp)
                        .fillMaxWidth()
                ) {
                    // 标题
                    Text(
                        modifier = Modifier.padding(bottom = 16.dp),
                        text = "API",
                        style = MaterialTheme.typography.titleLarge
                    )
                    // 选择API
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(Color.Gray.copy(alpha = 0.1f))
                            .clickable { isAPIDropdownExpanded = !isAPIDropdownExpanded }
                            .padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        // API 选择菜单
                        Row(
                            modifier = Modifier
                                .fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ){
                            Row(
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                // 显示创建API控件
                                if (onCreationAPI){
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        verticalAlignment = Alignment.CenterVertically
                                    ){
                                        OutlinedTextField(
                                            modifier = Modifier.weight(1f),
                                            value = creatingAPI.name,
                                            label = { Text("输入API名称") },
                                            maxLines = 1,
                                            onValueChange = {
                                                if (it.length < 30) {
                                                    creatingAPI = creatingAPI.copy(name = it)
                                                }
                                            }
                                        )
                                        Spacer(modifier = Modifier.width(8.dp))
                                        FilledTonalButton(
                                            onClick = { onCreationAPI = !onCreationAPI }
                                        ) {
                                            Text("取消")
                                        }

                                    }
                                }else{
                                    // 选择API菜单列表
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Text("选择API  ", style = MaterialTheme.typography.bodyLarge)
                                        Text(
                                            text = apiModel?.name ?: "选择API",
                                            style = MaterialTheme.typography.bodyLarge,
                                            color = if (apiModel == null) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.onBackground
                                        )
                                        DropdownMenu(
                                            modifier = Modifier.weight(1f),
                                            expanded = isAPIDropdownExpanded,
                                            onDismissRequest = { isAPIDropdownExpanded = false }
                                        ) {
                                            DropdownMenuItem(
                                                text = { Text("创建API连接") },
                                                onClick = {
                                                    onCreationAPI = true
                                                    isAPIDropdownExpanded = false
                                                }
                                            )
                                            apiList.forEach { api ->
                                                DropdownMenuItem(
                                                    text = { Text(api.name, style = MaterialTheme.typography.bodyLarge) },
                                                    onClick = {
                                                        isAPIDropdownExpanded = false
                                                        onSelectAPI(api)
                                                        onCreationAPI = false
                                                    }
                                                )
                                            }
                                        }
                                        if (apiModel != null) {
                                            Spacer(modifier = Modifier.weight(1f))
                                            OutlinedButton(
                                                onClick = onDelete,
                                                border = BorderStroke(1.dp, MaterialTheme.colorScheme.error),
                                                colors = ButtonDefaults.outlinedButtonColors(
                                                    contentColor = MaterialTheme.colorScheme.error, // 设置文字颜色为 error
                                                    containerColor = Color.Transparent // 背景保持透明
                                                ),
                                            ) {
                                                Text("删除", style = TextStyle(fontSize = 12.sp))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Spacer(modifier = Modifier.height(8.dp))

                    // API提供方选择菜单
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(Color.Gray.copy(alpha = 0.1f))
                            .clickable { isProviderDropdownExpanded = !isProviderDropdownExpanded }
                            .padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        // API 选择菜单
                        Row(
                            modifier = Modifier
                                .fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ){
                            Text("API 提供方：", style = MaterialTheme.typography.bodyLarge)
                            // 计算当前应该显示的API Provider
                            val currentAPIProvider = kotlin.run {
                                if (onCreationAPI || apiModel == null){
                                    creatingAPI
                                }else {
                                    apiModel
                                }
                            }
                            Row(
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(
                                    text = currentAPIProvider.apiProvider?.toValue() ?: "选择API提供方",
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = if (currentAPIProvider.apiProvider == null) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.onBackground
                                )
                                DropdownMenu(
                                    expanded = isProviderDropdownExpanded,
                                    onDismissRequest = { isProviderDropdownExpanded = false }
                                ) {
                                    apiProviderList.forEach { provider ->
                                        DropdownMenuItem(
                                            text = { Text(provider.toValue(), style = MaterialTheme.typography.bodyLarge) },
                                            onClick = {
                                                if (onCreationAPI || apiModel == null) {
                                                    creatingAPI = creatingAPI.copy(apiProvider = provider)
                                                }else {
                                                    updateAPI(apiModel.copy(apiProvider = provider))
                                                }
                                                isProviderDropdownExpanded = false
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }

                    // API地址编辑框
                    OutlinedTextField(
                        value = run {
                            if (onCreationAPI || apiModel == null) {
                                creatingAPI.apiUrl
                            }else {
                                apiModel.apiUrl
                            }
                        },
                        maxLines = 1,
                        onValueChange = {
                            if (onCreationAPI || apiModel == null) {
                                creatingAPI = creatingAPI.copy(apiUrl = it)
                            }else {
                                updateAPI(apiModel.copy(apiUrl = it))
                            }
                        },
                        label = { Text("API地址")}
                    )
                    // API路径编辑框
                    OutlinedTextField(
                        value = run {
                            if (onCreationAPI || apiModel == null) {
                                creatingAPI.apiPath
                            }else {
                                apiModel.apiPath
                            }
                        },
                        maxLines = 1,
                        onValueChange = {
                            if (onCreationAPI || apiModel == null) {
                                creatingAPI = creatingAPI.copy(apiPath = it)
                            }else {
                                updateAPI(apiModel.copy(apiPath = it))
                            }
                        },
                        label = { Text("API路径")}
                    )
                    // API秘钥
                    OutlinedTextField(
                        value = run {
                            if (onCreationAPI || apiModel == null) {
                                creatingAPI.apiKey
                            }else {
                                apiModel.apiKey
                            }
                        },
                        maxLines = 1,
                        onValueChange = {
                            if (onCreationAPI || apiModel == null) {
                                creatingAPI = creatingAPI.copy(apiKey = it)
                            }else {
                                updateAPI(apiModel.copy(apiKey = it))
                            }
                        },
                        label = { Text("API秘钥")},
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password), visualTransformation = PasswordVisualTransformation()
                    )
                    // 模型添加
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 12.dp)
                            .clip(RoundedCornerShape(16.dp))
                            .border(
                                width = 1.dp,
                                color = MaterialTheme.colorScheme.primaryContainer,
                                shape = RoundedCornerShape(16.dp)
                            ),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        var isAddModel by remember { mutableStateOf(false) }
                        var isError by remember { mutableStateOf(false) }
                        var newModel by remember { mutableStateOf("") }
                        LazyRow(
                            modifier = Modifier
                                .weight(1f),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            items(currentAPI.models) {model ->
                                var showDelete by remember { mutableStateOf(false) }
                                Card(
                                    colors = CardDefaults.cardColors(
                                        containerColor = MaterialTheme.colorScheme.primaryContainer
                                    ),
                                    shape = RoundedCornerShape(16.dp),
                                    modifier = Modifier
                                        .padding(horizontal = 4.dp)
                                        .combinedClickable(
                                            onClick = {},
                                            onLongClick = {
                                                showDelete = !showDelete
                                            }
                                        )
                                ){
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Text(model, modifier = Modifier.padding(6.dp), style = MaterialTheme.typography.bodyMedium)
                                        if (showDelete){
                                            IconButton(
                                                modifier = Modifier.size(16.dp),
                                                onClick = {
                                                    if(onCreationAPI || apiModel == null) {
                                                        creatingAPI = creatingAPI.copy(models = creatingAPI.models.filter { it != model })
                                                    }else {
                                                        updateAPI(apiModel.copy(models = apiModel.models.filter { it != model }))
                                                    }
                                                }
                                            ) {
                                                Icon( Icons.Outlined.Close, contentDescription = "删除模型"
                                                )
                                            }
                                            Spacer(modifier = Modifier.width(6.dp))
                                        }
                                    }
                                }
                            }
                            item {
                                val focusRequester = remember { FocusRequester() }
                                LaunchedEffect(isAddModel) {
                                    if (isAddModel) {
                                        // 当进入添加模式时，自动请求焦点
                                        focusRequester.requestFocus()
                                    }
                                }
                                if(isAddModel) {
                                    OutlinedTextField(
                                        value = newModel,
                                        maxLines = 1,
                                        onValueChange = {
                                            newModel = it
                                            isError = currentAPI.models.contains(newModel) && newModel.trim().isNotBlank()
                                        },
                                        label = { Text("模型名") },
                                        modifier = Modifier
                                            .width(150.dp)
                                            .padding(horizontal = 8.dp, vertical = 8.dp)
                                            .focusRequester(focusRequester),
                                        isError = isError,
                                        supportingText = { if (isError) { Text("模型名重复", color = MaterialTheme.colorScheme.error) } }
                                    )
                                }else {
                                    Card(
                                        colors = CardDefaults.cardColors(
                                            containerColor = MaterialTheme.colorScheme.primaryContainer
                                        ),
                                        shape = RoundedCornerShape(16.dp),
                                        modifier = Modifier
                                            .padding(horizontal = 4.dp)
                                            .clickable {
                                                isAddModel = true
                                            }
                                    ){
                                        Row(
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Spacer(modifier = Modifier.width(6.dp))
                                            Icon(Icons.Outlined.Add, contentDescription = "添加模型", modifier = Modifier.size(20.dp))
                                            Text("添加模型", modifier = Modifier.padding(6.dp), style = MaterialTheme.typography.bodyMedium)
                                            Spacer(modifier = Modifier.width(6.dp))
                                        }
                                    }
                                }

                            }

                        }
                        // 连接获取模型列表按钮
                        Card(
                            modifier = Modifier
                                .padding(12.dp)
                                .clickable {
                                    // 创建新模型
                                    if (isAddModel) {
                                        if (!isError && newModel.trim().isNotBlank()) {
                                            if (onCreationAPI || apiModel == null) {
                                                creatingAPI = creatingAPI.copy(
                                                    models = creatingAPI.models.toMutableList()
                                                        .apply {
                                                            add(newModel.trim())
                                                        }
                                                )
                                            } else {
                                                updateAPI(apiModel.copy(
                                                    models = apiModel.models.toMutableList().apply {
                                                        add(newModel.trim())
                                                    }
                                                ))
                                            }
                                            newModel = ""
                                            isAddModel = false
                                        } else if (newModel.trim().isBlank()) {
                                            newModel = ""
                                            isAddModel = false
                                        }
                                    } else {
                                        // TODO 获取模型列表
                                    }
                                },
                            shape = RoundedCornerShape(18.dp),
                            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primary)
                        ) {
                            Text(
                                text = run {
                                    if(isAddModel){
                                        if (newModel.trim().isBlank())
                                            "取消"
                                        else
                                            "完成"
                                    }
                                    else
                                        "获取模型"
                                },
                                modifier = Modifier.padding(8.dp),
                                style = TextStyle(fontSize = 12.sp)
                            )
                        }
                    }

                    // 上下文消息数量拖动条
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 16.dp)
                    ) {
                        val messagesSliderPosition = run {
                            if (currentAPI.contextMessages.toString().isBlank())
                                10.0f
                            else if (currentAPI.contextMessages.toFloat() >= 10)
                                currentAPI.contextMessages.toFloat()
                            else
                                10.0f
                        }
                        Text("记录最大上下文消息数", style = TextStyle(fontSize = 12.sp))
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {

                            // 滑块的最小值、最大值和步长
                            val minValue = 10f
                            val maxValue = 20000f
                            val step = 10f

                            // 计算 steps 参数：steps 是指滑块之间的间隔数
                            val steps = ((maxValue - minValue) / step).toInt() - 1

                            Slider(
                                value = messagesSliderPosition,
                                onValueChange = {
                                    if(onCreationAPI || apiModel == null) {
                                        creatingAPI = creatingAPI.copy(contextMessages = it.toInt())
                                    }else {
                                        updateAPI(apiModel.copy(contextMessages = it.toInt()))
                                    }
                                },
                                valueRange = minValue..maxValue, // 设置滑块范围为 10 到 20000
                                steps = steps, // 设置步数，确保只能选择整数值
                                modifier = Modifier.weight(1f)
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            OutlinedTextField(
                                modifier = Modifier
                                    .width(80.dp)
                                    .height(48.dp),
                                value = currentAPI.contextMessages.toString(),
                                maxLines = 1,
                                textStyle = TextStyle(fontSize = 14.sp),
                                onValueChange = { newValue ->
                                    if (newValue.isNotBlank() && newValue.toInt() > 20000){
                                        if (onCreationAPI || apiModel == null) {
                                            creatingAPI = creatingAPI.copy(contextMessages = 20000)
                                        }else {
                                            updateAPI(apiModel.copy(contextMessages = 20000))
                                        }
                                    }
                                    else if (onCreationAPI || apiModel == null){
                                        creatingAPI = creatingAPI.copy(contextMessages = if (newValue.isBlank()) 0 else ((newValue.toFloat() / step).roundToInt() * step).toInt() )
                                    }else {
                                        updateAPI(apiModel.copy(contextMessages = if (newValue.isBlank()) 0 else((newValue.toFloat() / step).roundToInt() * step).toInt()))
                                    }
                                },
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                            )
                        }
                    }

                    // 温度拖动条
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp)
                    ) {

                        val temperatureSliderPosition = currentAPI.temperature.toFloat()
                        Text("Temperature 参数", style = TextStyle(fontSize = 12.sp))
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {

                            // 滑块的最小值、最大值和步长
                            val minValue = 0f
                            val maxValue = 2f
                            val step = 0.1f
                            // 计算 steps 参数：steps 是指滑块之间的间隔数
                            val steps = ((maxValue - minValue) / step).toInt() - 1
                            Slider(
                                value = temperatureSliderPosition,
                                onValueChange = { newValue ->
                                    // 将滑块的值四舍五入到最近的步长，并保留一位小数
                                    val roundedValue = (newValue * 10).roundToInt() / 10f
                                    if(onCreationAPI || apiModel == null) {
                                        creatingAPI = creatingAPI.copy(temperature = roundedValue.toDouble())
                                    }else {
                                        updateAPI(apiModel.copy(temperature = roundedValue.toDouble()))
                                    }
                                },
                                steps = steps,
                                valueRange = minValue..maxValue, // 设置滑块范围为 0 到 2
                                modifier = Modifier.weight(1f)
                            )
                            Spacer(modifier = Modifier.width(16.dp))
                            Text(text = temperatureSliderPosition.toString())
                            Spacer(modifier = Modifier.width(16.dp))
                        }
                    }

                    // Top_P拖动条
                    Column(
                        modifier = Modifier.fillMaxWidth()
                    ) {

                        val topPSliderPosition = currentAPI.top_p.toFloat()
                        Text("Top P 参数", style = TextStyle(fontSize = 12.sp))
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {

                            // 滑块的最小值、最大值和步长
                            val minValue = 0f
                            val maxValue = 1f
                            val step = 0.1f
                            // 计算 steps 参数：steps 是指滑块之间的间隔数
                            val steps = ((maxValue - minValue) / step).toInt() - 1
                            Slider(
                                value = topPSliderPosition,
                                onValueChange = { newValue ->
                                    // 将滑块的值四舍五入到最近的步长，并保留一位小数
                                    val roundedValue = (newValue * 10).roundToInt() / 10f
                                    if(onCreationAPI || apiModel == null) {
                                        creatingAPI = creatingAPI.copy(top_p = roundedValue.toDouble())
                                    }else {
                                        updateAPI(apiModel.copy(top_p = roundedValue.toDouble()))
                                    }
                                },
                                steps = steps,
                                valueRange = minValue..maxValue, // 设置滑块范围为 0 到 2
                                modifier = Modifier.weight(1f)
                            )
                            Spacer(modifier = Modifier.width(16.dp))
                            Text(text = topPSliderPosition.toString())
                            Spacer(modifier = Modifier.width(16.dp))
                        }
                    }

                }

                Row (
                    horizontalArrangement = Arrangement.End,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 16.dp, end = 16.dp, bottom = 16.dp)
                ) {
                    TextButton(onClick = onDismiss) {
                        Text("取消")
                    }
                    Spacer(modifier = Modifier.weight(1f))
                    TextButton(
                        enabled = kotlin.run {
                            if (
                                currentAPI.name.trim().isBlank() ||
                                currentAPI.apiProvider == null ||
                                currentAPI.apiUrl.isBlank() ||
                                currentAPI.apiPath.isBlank() ||
                                currentAPI.temperature > 2 || creatingAPI.temperature < 0 ||
                                currentAPI.contextMessages > 20000 || creatingAPI.contextMessages < 10 ||
                                currentAPI.models.isEmpty() ||
                                currentAPI.top_p > 1 || creatingAPI.top_p < 0
                            )
                                false
                            else
                                true
                        },
                        onClick = {
                            if (onCreationAPI) {
                                onCreate(creatingAPI)
                                onCreationAPI = false
                                creatingAPI = newAPI
                            }else if (changed) {
                                onSave()
                            }else {
                                onDismiss()
                            }
                        }
                    ) {
                        Text(text = run {
                            if (onCreationAPI || apiModel == null)
                                "创建"
                            else if(changed)
                                "保存"
                            else
                                "确定"
                        })
                    }
                }


            }


        }
    }
}

