import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:now_chat/app/router.dart';
import 'package:now_chat/core/models/chat_session.dart';
import 'package:now_chat/core/models/ai_provider_config.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:now_chat/providers/settings_provider.dart';
import 'package:now_chat/ui/widgets/assistant_message_widget.dart';
import 'package:now_chat/ui/widgets/message_input.dart';
import 'package:now_chat/ui/widgets/system_prompt_message_item.dart';
import 'package:now_chat/ui/widgets/user_message_widget.dart';
import 'package:provider/provider.dart';
import '../widgets/model_selector_bottom_sheet.dart.dart';

class ChatDetailPage extends StatefulWidget {
  final int? chatId;

  const ChatDetailPage({super.key, this.chatId});

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  final ScrollController _scrollController = ScrollController();
  static const double _scrollBottomButtonThreshold = 420;

  ChatSession? _chat;

  String? _model;
  String? _providerId;
  bool _isStreaming = true;
  String _pendingSystemPrompt = '';
  List<String> _pendingAttachmentPaths = <String>[];
  bool _isRequestingMoreHistory = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    final chatProvider = context.read<ChatProvider>();
    // 如果有传入 chatId，则加载对应会话
    if (widget.chatId != null) {
      _chat = chatProvider.getChatById(widget.chatId!); // 加载当前会话的消息
      _pendingSystemPrompt = _chat?.systemPrompt ?? '';
      context.read<ChatProvider>().loadInitialMessages(widget.chatId!).then((_) {
        if (!mounted) return;
        _scrollToLatestOnEnter();
      });
    } else {
      final settings = context.read<SettingsProvider>();
      _providerId = settings.defaultProviderId;
      _model = settings.defaultModel;
      _isStreaming = settings.defaultStreaming;
      context.read<ChatProvider>().loadInitialMessages(null);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels > 120) return;
    _tryLoadMoreHistory();
  }

  Future<void> _tryLoadMoreHistory() async {
    if (_isRequestingMoreHistory) return;
    if (!_scrollController.hasClients) return;
    final chatProvider = context.read<ChatProvider>();
    if (!chatProvider.hasMoreHistory || chatProvider.isLoadingMoreHistory) {
      return;
    }

    _isRequestingMoreHistory = true;
    final oldMaxExtent = _scrollController.position.maxScrollExtent;
    final oldOffset = _scrollController.position.pixels;
    try {
      await chatProvider.loadMoreHistory();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) {
          _isRequestingMoreHistory = false;
          return;
        }
        final newMaxExtent = _scrollController.position.maxScrollExtent;
        final delta = newMaxExtent - oldMaxExtent;
        final targetOffset = (oldOffset + delta).clamp(0.0, newMaxExtent);
        _scrollController.jumpTo(targetOffset);
        _isRequestingMoreHistory = false;
      });
    } finally {
      if (!_scrollController.hasClients) {
        _isRequestingMoreHistory = false;
      }
    }
  }

  void _scrollToLatest({bool animated = false}) {
    if (!mounted) return;
    if (!_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToLatest(animated: animated);
      });
      return;
    }
    final target = _scrollController.position.maxScrollExtent;
    if (animated) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  void _scrollToLatestOnEnter() {
    _scrollToLatest();
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      _scrollToLatest();
    });
    Future<void>.delayed(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      _scrollToLatest();
    });
    Future<void>.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      _scrollToLatest();
    });
  }

  void _scrollToLatestAfterSend() {
    _scrollToLatest(animated: true);
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      _scrollToLatest(animated: true);
    });
    Future<void>.delayed(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      _scrollToLatest(animated: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final messages = chatProvider.currentMessages;

    final effectiveChatId = widget.chatId ?? _chat?.id;
    final chat =
        effectiveChatId == null
            ? null
            : (chatProvider.getChatById(effectiveChatId) ?? _chat);
    final selectedProviderId = chat?.providerId ?? _providerId;
    final selectedProvider =
        selectedProviderId == null
            ? null
            : chatProvider.getProviderById(selectedProviderId);
    final selectedModelRaw = chat?.model ?? _model;
    final selectedModelDisplay =
        selectedModelRaw == null
            ? null
            : (selectedProvider?.displayNameForModel(selectedModelRaw) ??
                selectedModelRaw);
    final selectedModelFeatures =
        selectedProvider != null && selectedModelRaw != null
            ? selectedProvider.featuresForModel(selectedModelRaw)
            : const ModelFeatureOptions();
    final streamingSupported =
        selectedProvider?.requestMode.supportsStreaming ?? true;
    final shouldShowScrollToBottomButton =
        _scrollController.hasClients &&
        (_scrollController.position.maxScrollExtent -
                _scrollController.position.pixels >
            _scrollBottomButtonThreshold);
    final activeSystemPrompt =
        (chat?.systemPrompt ?? _pendingSystemPrompt).trim();
    final hasSystemPrompt = activeSystemPrompt.isNotEmpty;
    if (chat != null && _pendingSystemPrompt != (chat.systemPrompt ?? '')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _pendingSystemPrompt = chat.systemPrompt ?? '';
        });
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(chat?.title ?? "新会话"),
        actions: [
          if (chat != null)
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: '会话设置',
              onPressed: () async {
                final result = await Navigator.pushNamed(
                  context,
                  AppRoutes.chatSettings,
                  arguments: {'chatId': chat.id},
                );
                if (!mounted) return;
                final refreshed = chatProvider.getChatById(chat.id);
                final returnedPrompt =
                    (result is Map ? result['systemPrompt'] : null)
                        ?.toString() ??
                    '';
                setState(() {
                  if (refreshed != null) {
                    _chat = refreshed;
                    _pendingSystemPrompt = refreshed.systemPrompt ?? '';
                  } else if (result is Map && result['saved'] == true) {
                    _pendingSystemPrompt = returnedPrompt;
                  }
                });
                await chatProvider.loadInitialMessages(chat.id);
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // 聊天内容区
          Expanded(
            child: Stack(
              children: [
                chat == null
                    ? ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(top: 8),
                      children: [
                        SystemPromptMessageItem(
                          text: _pendingSystemPrompt,
                          isPlaceholder: _pendingSystemPrompt.trim().isEmpty,
                          onTap: () => _showSystemPromptEditor(chat: null),
                        ),
                        const SizedBox(height: 24),
                        const Center(child: Text("发送消息以开始新的会话")),
                      ],
                    )
                    : ListView.builder(
                      controller: _scrollController,
                      itemCount:
                          messages.length +
                          (hasSystemPrompt ? 1 : 0) +
                          (chatProvider.isLoadingMoreHistory ? 1 : 0),
                      itemBuilder: (context, index) {
                        var cursor = index;
                        if (hasSystemPrompt && cursor == 0) {
                          return SystemPromptMessageItem(
                            text: activeSystemPrompt,
                            onTap: () => _showSystemPromptEditor(chat: chat),
                          );
                        }
                        if (hasSystemPrompt) {
                          cursor -= 1;
                        }
                        if (chatProvider.isLoadingMoreHistory && cursor == 0) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          );
                        }
                        if (chatProvider.isLoadingMoreHistory) {
                          cursor -= 1;
                        }
                        final msg = messages[cursor];
                        final isLastMessage = cursor == messages.length - 1;
                        if (msg.role == "user") {
                          return UserMessageWidget(
                            key: ValueKey('user-${msg.isarId}'),
                            message: msg,
                            onDelete:
                                () => chatProvider.deleteMessage(msg.isarId),
                          );
                        } else if (msg.role == "assistant") {
                          final showContinueButton =
                              isLastMessage &&
                              chatProvider.canContinueAssistantMessage(
                                chat.id,
                                msg.isarId,
                              );
                          return AssistantMessageWidget(
                            key: ValueKey('assistant-${msg.isarId}'),
                            message: msg,
                            isGenerating: chat.isGenerating,
                            isStreamingMessage: chatProvider.isMessageStreaming(
                              msg.isarId,
                            ),
                            showResendButton: isLastMessage,
                            showContinueButton: showContinueButton,
                            onResend: () async {
                              await chatProvider.regenerateMessage(
                                chat.id,
                                chat.isStreaming,
                              );
                            },
                            onContinue: () async {
                              await chatProvider
                                  .continueGeneratingAssistantMessage(
                                    chat.id,
                                    chat.isStreaming,
                                  );
                            },
                            onDelete:
                                () => chatProvider.deleteMessage(msg.isarId),
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
                      onPressed: () {
                        _scrollToLatest(animated: true);
                      },
                      child: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ),
              ],
            ),
          ),

          // 输入框
          MessageInput(
            chat: chat,
            model: selectedModelDisplay,
            isGenerating: chat?.isGenerating ?? false,
            modelSupportsVision: selectedModelFeatures.supportsVision,
            modelSupportsTools: selectedModelFeatures.supportsTools,
            attachments: _pendingAttachmentPaths,
            onSend: (text, attachments) async {
              final settings = context.read<SettingsProvider>();
              final attachmentsToSend = List<String>.from(attachments);
              // 如果还没有会话，则新建
              if (chat == null) {
                final newChat = await chatProvider.createNewChat();
                // 标题为发送内容前20个字
                final fallbackTitle =
                    attachmentsToSend.isNotEmpty
                        ? '附件: ${_attachmentName(attachmentsToSend.first)}'
                        : '新会话';
                final rawTitle = text.isEmpty ? fallbackTitle : text;
                final title =
                    rawTitle.length > 20 ? rawTitle.substring(0, 20) : rawTitle;
                chatProvider.renameChat(newChat.id, title);
                String? candidateProviderId = _providerId?.trim();
                if (candidateProviderId == null || candidateProviderId.isEmpty) {
                  candidateProviderId = settings.defaultProviderId?.trim();
                }
                if (candidateProviderId != null &&
                    candidateProviderId.isEmpty) {
                  candidateProviderId = null;
                }

                String? candidateModel = _model?.trim();
                if (candidateModel == null || candidateModel.isEmpty) {
                  candidateModel = settings.defaultModel?.trim();
                }
                if (candidateModel != null && candidateModel.isEmpty) {
                  candidateModel = null;
                }

                final providerForNewChat =
                    candidateProviderId == null
                        ? null
                        : chatProvider.getProviderById(candidateProviderId);
                if (providerForNewChat == null) {
                  candidateModel = null;
                } else if (candidateModel != null &&
                    !providerForNewChat.models.contains(candidateModel)) {
                  candidateModel = null;
                }
                final supportsStreaming =
                    providerForNewChat?.requestMode.supportsStreaming ?? true;
                final isStreamingForNewChat =
                    supportsStreaming
                        ? (_chat?.isStreaming ?? _isStreaming)
                        : false;

                chatProvider.updateChat(
                  newChat,
                  model: candidateModel,
                  providerId: providerForNewChat?.id,
                  systemPrompt: _pendingSystemPrompt.trim(),
                  temperature: settings.defaultTemperature,
                  topP: settings.defaultTopP,
                  maxTokens: settings.defaultMaxTokens,
                  maxConversationTurns: settings.defaultMaxConversationTurns,
                  isStreaming: isStreamingForNewChat,
                );
                setState(() {
                  _chat = newChat;
                });
              }
              _scrollToLatestAfterSend();
              await chatProvider.sendMessage(
                _chat!.id,
                text,
                _chat!.isStreaming,
                attachmentsToSend,
              );
              if (mounted) {
                setState(() {
                  _pendingAttachmentPaths = <String>[];
                });
              }
            },
            onModelSelected: () async {
              _showModelSelector(context);
            },
            onStopGenerating: () {
              if (chat != null) {
                chatProvider.interruptGeneration(chat.id);
              }
            },
            onPickImage:
                () => _pickImages(
                  selectedProvider: selectedProvider,
                  selectedModelRaw: selectedModelRaw,
                  features: selectedModelFeatures,
                ),
            onPickFile:
                () => _pickFiles(
                  selectedProvider: selectedProvider,
                  selectedModelRaw: selectedModelRaw,
                  features: selectedModelFeatures,
                ),
            onRemoveAttachment: (path) {
              setState(() {
                _pendingAttachmentPaths.remove(path);
              });
            },
            isStreaming: _chat?.isStreaming ?? _isStreaming,
            streamingSupported: streamingSupported,
            streamingChanged: (bool? value) {
              if (!streamingSupported) return;
              if (chat != null) {
                chatProvider.updateChat(chat, isStreaming: value!);
              } else {
                setState(() {
                  _isStreaming = value!;
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showSystemPromptEditor({required ChatSession? chat}) async {
    final chatProvider = context.read<ChatProvider>();
    final initial = chat?.systemPrompt ?? _pendingSystemPrompt;
    final controller = TextEditingController(text: initial);

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('设置 System Prompt'),
          content: TextField(
            controller: controller,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '输入本会话专用的系统提示词（可选）',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, ''),
              child: const Text('清空'),
            ),
            FilledButton(
              onPressed:
                  () => Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (result == null) return;
    if (chat != null) {
      await chatProvider.updateChat(
        chat,
        systemPrompt: result,
        lastUpdated: DateTime.now(),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _pendingSystemPrompt = result;
    });
  }

  String _attachmentName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    if (idx == -1 || idx == normalized.length - 1) return normalized;
    return normalized.substring(idx + 1);
  }

  void _appendPendingAttachments(List<String> newPaths) {
    if (newPaths.isEmpty) return;
    setState(() {
      for (final path in newPaths) {
        if (_pendingAttachmentPaths.contains(path)) continue;
        _pendingAttachmentPaths.add(path);
      }
    });
  }

  Future<void> _pickImages({
    required AIProviderConfig? selectedProvider,
    required String? selectedModelRaw,
    required ModelFeatureOptions features,
  }) async {
    if (selectedProvider != null &&
        selectedModelRaw != null &&
        !features.supportsVision) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前模型未开启视觉能力')));
      return;
    }

    final picker = ImagePicker();
    final images = await picker.pickMultiImage();
    if (images.isEmpty) return;
    final paths =
        images
            .map((img) => img.path.trim())
            .where((p) => p.isNotEmpty)
            .toList();
    _appendPendingAttachments(paths);
  }

  Future<void> _pickFiles({
    required AIProviderConfig? selectedProvider,
    required String? selectedModelRaw,
    required ModelFeatureOptions features,
  }) async {
    if (selectedProvider != null &&
        selectedModelRaw != null &&
        !features.supportsTools) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前模型未开启工具能力')));
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );
    if (result == null) return;
    final paths =
        result.files
            .map((file) => (file.path ?? '').trim())
            .where((p) => p.isNotEmpty)
            .toList();
    _appendPendingAttachments(paths);
  }

  // 选择模型
  void _showModelSelector(BuildContext context) {
    final chatProvider = context.read<ChatProvider>();
    final chat =
        widget.chatId != null
            ? chatProvider.getChatById(widget.chatId!)
            : _chat;
    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true, // 若内容较多可滚动
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      builder:
          (context) => ModelSelectorBottomSheet(
            onModelSelected: (providerId, model) {
              if (chat != null) {
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
