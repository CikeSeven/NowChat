import 'package:flutter/material.dart';
import 'package:now_chat/core/models/chat_session.dart';
import 'package:now_chat/core/models/message.dart';
import 'package:now_chat/ui/widgets/assistant_message_widget.dart';
import 'package:now_chat/ui/widgets/system_prompt_message_item.dart';
import 'package:now_chat/ui/widgets/user_message_widget.dart';

class ChatMessageListPanel extends StatelessWidget {
  final ChatSession? chat;
  final ScrollController scrollController;
  final List<Message> messages;
  final bool hasSystemPrompt;
  final String activeSystemPrompt;
  final bool isLoadingMoreHistory;
  final bool shouldShowScrollToBottomButton;
  final VoidCallback onTapSystemPrompt;
  final VoidCallback onScrollToBottom;
  final Future<void> Function() onResendLastAssistant;
  final Future<void> Function() onContinueLastAssistant;
  final Future<void> Function(int messageIsarId) onDeleteMessage;
  final bool Function(int messageIsarId) isMessageStreaming;
  final bool Function(int messageIsarId) canContinueAssistantMessage;

  const ChatMessageListPanel({
    super.key,
    required this.chat,
    required this.scrollController,
    required this.messages,
    required this.hasSystemPrompt,
    required this.activeSystemPrompt,
    required this.isLoadingMoreHistory,
    required this.shouldShowScrollToBottomButton,
    required this.onTapSystemPrompt,
    required this.onScrollToBottom,
    required this.onResendLastAssistant,
    required this.onContinueLastAssistant,
    required this.onDeleteMessage,
    required this.isMessageStreaming,
    required this.canContinueAssistantMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        chat == null
            ? ListView(
              controller: scrollController,
              padding: const EdgeInsets.only(top: 8),
              children: [
                SystemPromptMessageItem(
                  text: activeSystemPrompt,
                  isPlaceholder: activeSystemPrompt.trim().isEmpty,
                  onTap: onTapSystemPrompt,
                ),
                const SizedBox(height: 24),
                const Center(child: Text('发送消息以开始新的会话')),
              ],
            )
            : ListView.builder(
              controller: scrollController,
              itemCount:
                  messages.length +
                  (hasSystemPrompt ? 1 : 0) +
                  (isLoadingMoreHistory ? 1 : 0),
              itemBuilder: (context, index) {
                var cursor = index;
                if (hasSystemPrompt && cursor == 0) {
                  return SystemPromptMessageItem(
                    text: activeSystemPrompt,
                    onTap: onTapSystemPrompt,
                  );
                }
                if (hasSystemPrompt) {
                  cursor -= 1;
                }
                if (isLoadingMoreHistory && cursor == 0) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                if (isLoadingMoreHistory) {
                  cursor -= 1;
                }
                final msg = messages[cursor];
                final isLastMessage = cursor == messages.length - 1;
                if (msg.role == 'user') {
                  return UserMessageWidget(
                    key: ValueKey('user-${msg.isarId}'),
                    message: msg,
                    onDelete: () => onDeleteMessage(msg.isarId),
                  );
                }
                if (msg.role == 'assistant') {
                  final showContinueButton =
                      isLastMessage && canContinueAssistantMessage(msg.isarId);
                  return AssistantMessageWidget(
                    key: ValueKey('assistant-${msg.isarId}'),
                    message: msg,
                    isGenerating: chat!.isGenerating,
                    isStreamingMessage: isMessageStreaming(msg.isarId),
                    showResendButton: isLastMessage,
                    showContinueButton: showContinueButton,
                    onResend: onResendLastAssistant,
                    onContinue: onContinueLastAssistant,
                    onDelete: () => onDeleteMessage(msg.isarId),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
        if (chat != null && shouldShowScrollToBottomButton)
          Positioned(
            right: 14,
            bottom: 16,
            child: FloatingActionButton.small(
              heroTag: 'chat_scroll_to_bottom_btn',
              onPressed: onScrollToBottom,
              child: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
          ),
      ],
    );
  }
}
