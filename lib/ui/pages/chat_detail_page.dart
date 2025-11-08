import 'package:flutter/material.dart';
import 'package:now_chat/core/models/chat_session.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:now_chat/ui/widgets/assistant_message_widget.dart';
import 'package:now_chat/ui/widgets/message_input.dart';
import 'package:now_chat/ui/widgets/user_message_widget.dart';
import 'package:now_chat/util/app_logger.dart';
import 'package:provider/provider.dart';
import '../widgets/model_selector_bottom_sheet.dart.dart';

class ChatDetailPage extends StatefulWidget {
  final int? chatId;

  const ChatDetailPage({
    super.key,
    this.chatId,
  });

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  final ScrollController _scrollController = ScrollController();

  ChatSession? _chat;

  String? _model;
  String? _providerId;
  bool _isStreaming = true;

  @override
  void initState() {
    super.initState();
    final chatProvider = context.read<ChatProvider>();
    // 如果有传入 chatId，则加载对应会话
    if (widget.chatId != null) {
      _chat = chatProvider.getChatById(widget.chatId!);// 加载当前会话的消息
      context.read<ChatProvider>().loadMessages(widget.chatId!);
    } else {
      context.read<ChatProvider>().loadMessages(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final messages = chatProvider.currentMessages;

    final chat = widget.chatId != null
      ? chatProvider.getChatById(widget.chatId!) 
      : _chat;

    return Scaffold(
      appBar: AppBar(
        title: Text(chat?.title ?? "新会话"),
      ),
      body: Column(
        children: [
          // 聊天内容区
          Expanded(
            child: chat == null
                ? const Center(
                    child: Text("发送消息以开始新的会话"),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      if (msg.role == "user") {
                        return UserMessageWidget(message: msg);
                      } else if (msg.role == "assistant") {
                        return AssistantMessageWidget(message: msg, isGenerating: chat.isGenerating,);
                      }
                      return const SizedBox.shrink();
                    },
                  ),
          ),

          // 输入框
          MessageInput(
            chat: chat,
            model: _model,
            onSend: (text) async {
              // 如果还没有会话，则新建
              if (chat == null) {
                final newChat = await chatProvider.createNewChat();
                // 标题为发送内容前20个字
                final title = text.length > 20 ? text.substring(0, 20) : text;
                chatProvider.renameChat(newChat.id, title);
                chatProvider.updateChat(
                  newChat,
                  model: _model,
                  providerId: _providerId,
                  isStreaming: _chat?.isStreaming ?? _isStreaming
                );
                setState(() {
                  _chat = newChat;
                });
              }
              await chatProvider.sendMessage(_chat!.id, text, _chat!.isStreaming);
            },
            onModelSelected: () async {
              _showModelSelector(context);
            },
            isStreaming: _chat?.isStreaming ?? _isStreaming,
            streamingChanged: (bool? value) {
              if (chat != null) {
                chatProvider.updateChat(chat, isStreaming: value!);
              } else {
                setState(() {
                  _isStreaming = value!;
                });
              }
            },
          )
        ],
      ),
    );
  }


  // 选择模型
  void _showModelSelector(BuildContext context) {
    final chatProvider = context.read<ChatProvider>();
    final chat = widget.chatId != null
      ? chatProvider.getChatById(widget.chatId!)
      : _chat;
    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true, // 若内容较多可滚动
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      builder: (context) => ModelSelectorBottomSheet(
        onModelSelected: (providerId, model) {
          if(chat != null) {
            chatProvider.updateChat(
              chat,
              providerId: providerId,
              model: model,
            );
          } else {
            setState(() {
              _providerId = providerId;
              _model = model;
            });
          }
          Navigator.pop(context);
        },
        providerId: chat == null ? _providerId : chat.providerId,
        model: chat == null ? _model : chat.model,
      ),
    );
  }
}