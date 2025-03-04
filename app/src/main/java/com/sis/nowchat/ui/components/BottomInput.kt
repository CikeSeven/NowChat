package com.sis.nowchat.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Send
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Send
import androidx.compose.material.icons.outlined.Square
import androidx.compose.material.icons.outlined.Stop
import androidx.compose.material.icons.outlined.VideoCameraBack
import androidx.compose.material.icons.outlined.Videocam
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun BottomInput(
    content: String,
    onValueChange: (String) -> Unit,
    modelList: (List<String>),
    currentModel: String,
    selectedModel: (String) -> Unit,
    onSendClick: () -> Unit,
    isResponding: Boolean
) {
    val minHeight = 38.dp // 最小高度
    val maxHeight = 200.dp // 最大高度
    val cornerRadius = 32.dp // 圆角半径
    val dividerStrokeWidth = 0.5.dp // 分割线宽度

    var showMore by remember { mutableStateOf(false) }
    // 根据 showMore 动态计算旋转角度
    val rotationAngle by animateFloatAsState(targetValue = if (showMore) 225f else 0f)

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .imePadding()
    ){

        // 使用 Canvas 绘制弧度分割线
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(cornerRadius)
                .clip(shape = RectangleShape) // 裁剪掉下半部分
        ){
            Canvas(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(cornerRadius * 2) // 高度为圆角半径的两倍
            ) {
                val cornerRadiusPx = cornerRadius.toPx() // 将 dp 转换为像素
                val strokeWidthPx = dividerStrokeWidth.toPx() // 将 dp 转换为像素

                // 绘制顶部弧度分割线
                drawRoundRect(
                    color = Color.Gray.copy(alpha = 0.3f), // 分割线颜色
                    topLeft = Offset.Zero,
                    size = Size(size.width, cornerRadiusPx * 2),
                    cornerRadius = CornerRadius(cornerRadiusPx), // 使用 CornerRadius 定义圆角
                    style = Stroke(width = strokeWidthPx)
                )
            }
        }

        // 主容器：Column 布局
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .imePadding()   // 根据键盘调整位置
                .clip(RoundedCornerShape(topStart = cornerRadius, topEnd = cornerRadius)) // 顶部圆角
                .padding(start = 16.dp, end = 16.dp, top = 20.dp)
        ) {
            // 编辑框部分
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = minHeight, max = maxHeight) // 动态高度范围
                    .background(
                        color = Color.Gray.copy(alpha = 0.1f), // 灰色背景
                        shape = RoundedCornerShape(24.dp) // 圆角
                    )
            ) {

                TextField(
                    value = content,
                    onValueChange = onValueChange,
                    modifier = Modifier.fillMaxWidth(),
                    textStyle = TextStyle(fontSize = 16.sp, lineHeight = 16.sp),
                    colors = TextFieldDefaults.colors(
                        unfocusedContainerColor = Color.Transparent,
                        focusedContainerColor = Color.Transparent,
                        disabledContainerColor = Color.Transparent,
                        focusedIndicatorColor = Color.Transparent,
                        unfocusedIndicatorColor = Color.Transparent,
                        disabledIndicatorColor = Color.Transparent
                    ),
                    placeholder = {
                        Text("开始聊天吧！", color = Color.Gray)
                    },
                    singleLine = false
                )
            }

            // 按钮栏部分
            Row(
                modifier = Modifier
                    .padding(top = 4.dp)
                    .fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // 左边的加号按钮
                IconButton(
                    onClick = {
                        showMore = !showMore
                    },
                    modifier = Modifier.size(32.dp)
                ) {
                    Icon(Icons.Outlined.AddCircleOutline, modifier = Modifier.rotate(rotationAngle), contentDescription = "更多")
                }

                // 模型列表
                LazyRow(
                    modifier = Modifier
                        .weight(1f)
                        .padding(start = 8.dp, end = 16.dp)
                ) {
                    items(modelList){modelName ->
                        Card(
                            colors = CardDefaults.cardColors(
                                containerColor = if (currentModel == modelName) MaterialTheme.colorScheme.primaryContainer else Color.Gray.copy(alpha = 0.2f)
                            ),
                            onClick = { selectedModel(modelName) },
                            shape = RoundedCornerShape(16.dp),
                            modifier = Modifier
                                .padding(horizontal = 4.dp)
                        ){
                            Text(modelName, modifier = Modifier.padding(6.dp), style = TextStyle(fontSize = 12.sp))
                        }
                    }
                }

                // 右边的发送按钮
                IconButton(
                    onClick = {
                        if (content.isNotEmpty() || isResponding) {
                            onSendClick()
                        }
                    },
                    enabled = content.isNotBlank() || isResponding,
                    modifier = Modifier.size(32.dp)
                ) {
                    Icon(
                        if (isResponding) Icons.Outlined.Stop
                        else Icons.AutoMirrored.Outlined.Send,
                        contentDescription = if (isResponding) "停止" else "发送"
                    )
                }
            }

            // 加号展开更多操作
            AnimatedVisibility(showMore) {
                HorizontalDivider(modifier = Modifier.padding(horizontal = 32.dp))
                Row(
                    modifier = Modifier
                        .padding(top = 12.dp)
                        .fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ){
                    Column(
                        modifier = Modifier
                            .clickable { }
                            .weight(1f),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Icon(Icons.Outlined.Image, contentDescription = null)
                        Spacer(modifier = Modifier.height(8.dp))
                        Text("图片")
                    }
                    Spacer(modifier = Modifier.width(28.dp))
                    VerticalDivider(modifier = Modifier.height(38.dp))
                    Spacer(modifier = Modifier.width(28.dp))
                    Column(
                        modifier = Modifier
                            .clickable { }
                            .weight(1f),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Icon(Icons.Outlined.VideoCameraBack, contentDescription = null)
                        Spacer(modifier = Modifier.height(8.dp))
                        Text("拍摄")
                    }
                }
            }

        }
    }

}