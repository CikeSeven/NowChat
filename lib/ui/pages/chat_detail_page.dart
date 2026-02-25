import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:now_chat/app/router.dart';
import 'package:now_chat/core/models/chat_session.dart';
import 'package:now_chat/core/models/ai_provider_config.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:now_chat/providers/settings_provider.dart';
import 'package:now_chat/ui/widgets/chat_webview_panel.dart';
import 'package:now_chat/ui/pages/image_preview_page.dart';
import 'package:now_chat/ui/widgets/message_bottom_sheet_menu.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/model_selector_bottom_sheet.dart.dart';

/// ChatDetailPage 页面。
class ChatDetailPage extends StatefulWidget {
  final int? chatId;

  const ChatDetailPage({super.key, this.chatId});

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

/// _ChatDetailPageState 视图状态。
class _ChatDetailPageState extends State<ChatDetailPage> {
  ChatSession? _chat;

  String? _model;
  String? _providerId;
  bool _isStreaming = true;
  String _pendingSystemPrompt = '';
  List<String> _pendingAttachmentPaths = <String>[];
  bool _defaultsInitialized = false;

  @override
  void initState() {
    super.initState();
    final chatProvider = context.read<ChatProvider>();
    // 如果有传入 chatId，则按”打开已有会话”流程初始化。
    if (widget.chatId != null) {
      _chat = chatProvider.getChatById(widget.chatId!);
      _pendingSystemPrompt = _chat?.systemPrompt ?? '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<ChatProvider>().loadInitialMessages(widget.chatId!);
      });
    } else {
      // 新建会话入口：先清空当前消息缓存，避免沿用上一会话内容。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<ChatProvider>().loadInitialMessages(null);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_defaultsInitialized) return;
    _defaultsInitialized = true;
    if (widget.chatId != null) return;
    try {
      final settings = context.read<SettingsProvider>();
      _providerId = settings.defaultProviderId;
      _model = settings.defaultModel;
      _isStreaming = settings.defaultStreaming;
    } catch (_) {
      // 忽略默认设置读取失败，保持新会话可用。
    }
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
    final activeSystemPrompt =
        (chat?.systemPrompt ?? _pendingSystemPrompt).trim();
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
      body: ChatWebViewPanel(
        chat: chat,
        messages: messages,
        model: selectedModelDisplay,
        isGenerating: chat?.isGenerating ?? false,
        modelSupportsVision: selectedModelFeatures.supportsVision,
        modelSupportsTools: selectedModelFeatures.supportsTools,
        isStreaming: _chat?.isStreaming ?? _isStreaming,
        streamingSupported: streamingSupported,
        systemPrompt: activeSystemPrompt,
        attachments: _pendingAttachmentPaths,
        isLoadingMoreHistory: chatProvider.isLoadingMoreHistory,
        onSendMessage: (text) async {
          final settings = context.read<SettingsProvider>();
          final attachmentsToSend = List<String>.from(_pendingAttachmentPaths);
          // 如果还没有会话，则新建并落默认参数。
          if (chat == null) {
            final newChat = await chatProvider.createNewChat();
            await chatProvider.loadInitialMessages(newChat.id);
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
              toolCallingEnabled: settings.defaultToolCallingEnabled,
              maxToolCalls: settings.defaultMaxToolCalls,
              isStreaming: isStreamingForNewChat,
            );
            setState(() {
              _chat = newChat;
            });
          }
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
            _pendingAttachmentPaths =
                _pendingAttachmentPaths.where((p) => p != path).toList();
          });
        },
        onSelectModel: () => _showModelSelector(context),
        onStreamingChanged: (value) {
          if (!streamingSupported) return;
          if (chat != null) {
            chatProvider.updateChat(chat, isStreaming: value);
          } else {
            setState(() {
              _isStreaming = value;
            });
          }
        },
        onScrollNearTop: () {
          _tryLoadMoreHistory();
        },
        onMessageAction: (id, action) {
          _handleMessageAction(chatProvider, chat, id, action);
        },
        onShowAttachmentMenu: () {
          _showAttachmentMenu(
            selectedProvider: selectedProvider,
            selectedModelRaw: selectedModelRaw,
            features: selectedModelFeatures,
          );
        },
        onUserMessageLongPress: (id) {
          _showUserMessageMenu(chatProvider, id);
        },
        onLinkTap: (url) {
          final uri = Uri.tryParse(url);
          if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        onImageTap: (url) {
          final uri = Uri.tryParse(url);
          if (uri != null) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ImagePreviewPage(imageUri: uri),
              ),
            );
          }
        },
        isMessageStreaming: chatProvider.isMessageStreaming,
        canContinueAssistantMessage:
            (messageIsarId) =>
                chat == null
                    ? false
                    : chatProvider.canContinueAssistantMessage(
                      chat.id,
                      messageIsarId,
                    ),
        toolLogsForMessage: chatProvider.toolLogsForMessage,
      ),
    );
  }

  /// 处理 WebView 侧消息操作回调。
  void _handleMessageAction(
    ChatProvider chatProvider,
    ChatSession? chat,
    int messageId,
    String action,
  ) {
    // WebView 回调在极端重建时可能携带旧闭包中的 null chat，
    // 这里统一回查可用会话，避免“继续/重发点击无响应”。
    final effectiveChat =
        chat ??
        _chat ??
        (widget.chatId == null ? null : chatProvider.getChatById(widget.chatId!));
    final normalizedAction = action.trim();

    switch (normalizedAction) {
      case 'resend':
        if (effectiveChat != null) {
          chatProvider.regenerateMessage(
            effectiveChat.id,
            effectiveChat.isStreaming,
          );
        }
        break;
      case 'continue':
        if (effectiveChat != null) {
          chatProvider.continueGeneratingAssistantMessage(
            effectiveChat.id,
            effectiveChat.isStreaming,
          );
        }
        break;
      case 'delete':
        chatProvider.deleteMessage(messageId);
        break;
      case 'edit':
        final msg = chatProvider.currentMessages
            .where((m) => m.isarId == messageId)
            .firstOrNull;
        if (msg != null) {
          Navigator.pushNamed(
            context,
            AppRoutes.editMessage,
            arguments: msg,
          );
        }
        break;
      case 'editSystemPrompt':
        _showSystemPromptEditor(chat: chat);
        break;
      case 'copy':
        final msg = chatProvider.currentMessages
            .where((m) => m.isarId == messageId)
            .firstOrNull;
        if (msg != null) {
          Clipboard.setData(ClipboardData(text: msg.content));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
            );
          }
        }
        break;
      case 'longpress':
      case 'more':
        _showAssistantMessageMenu(chatProvider, chat, messageId);
        break;
    }
  }

  /// 加载更多历史消息。
  Future<void> _tryLoadMoreHistory() async {
    final chatProvider = context.read<ChatProvider>();
    if (!chatProvider.hasMoreHistory || chatProvider.isLoadingMoreHistory) {
      return;
    }
    await chatProvider.loadMoreHistory();
  }

  Future<void> _showSystemPromptEditor({required ChatSession? chat}) async {
    final chatProvider = context.read<ChatProvider>();
    final initial = chat?.systemPrompt ?? _pendingSystemPrompt;
    var draft = initial;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('设置 System Prompt'),
          content: TextFormField(
            initialValue: initial,
            onChanged: (value) {
              draft = value;
            },
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
              onPressed: () => Navigator.pop(dialogContext, draft.trim()),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

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

  /// 二次确认弹窗，返回 true 表示用户确认。
  Future<bool> _confirmAction(String title, String content) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    return result == true;
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
      final next = List<String>.from(_pendingAttachmentPaths);
      for (final path in newPaths) {
        if (next.contains(path)) continue;
        next.add(path);
      }
      _pendingAttachmentPaths = next;
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

  /// 弹出附件选择菜单（上传图片/上传文件）。
  Future<void> _showAttachmentMenu({
    required AIProviderConfig? selectedProvider,
    required String? selectedModelRaw,
    required ModelFeatureOptions features,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('上传图片'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImages(
                    selectedProvider: selectedProvider,
                    selectedModelRaw: selectedModelRaw,
                    features: features,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_file_outlined),
                title: const Text('上传文件'),
                onTap: () {
                  Navigator.pop(context);
                  _pickFiles(
                    selectedProvider: selectedProvider,
                    selectedModelRaw: selectedModelRaw,
                    features: features,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// 用户消息长按菜单。
  void _showUserMessageMenu(ChatProvider chatProvider, int messageId) {
    final color = Theme.of(context).colorScheme;
    final msg = chatProvider.currentMessages
        .where((m) => m.isarId == messageId)
        .firstOrNull;
    if (msg == null) return;
    showModalBottomSheetMenu(
      context: context,
      message: msg,
      items: [
        SheetMenuItem(
          icon: const Icon(Icons.edit_outlined),
          label: '编辑',
          onTap: () {
            Navigator.pushNamed(context, AppRoutes.editMessage, arguments: msg);
          },
        ),
        SheetMenuItem(
          icon: const Icon(Icons.copy_outlined),
          label: '复制',
          onTap: () {
            Clipboard.setData(ClipboardData(text: msg.content));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
            );
          },
        ),
        SheetMenuItem(
          icon: Icon(Icons.delete_outline, color: color.error,),
          label: '删除',
          onTap: () async {
            final confirmed = await _confirmAction('删除确认', '确定要删除这条消息吗？');
            if (confirmed) chatProvider.deleteMessage(messageId);
          },
        ),
        SheetMenuItem(
          icon: Icon(Icons.delete_forever, color: color.error,),
          label: '删除这条及之后的消息',
          onTap: () async {
            final confirmed = await _confirmAction('删除确认', '将删除此消息及之后的所有消息，是否继续？');
            if (confirmed) chatProvider.deleteMessageAndAfter(messageId);
          },
        ),
      ],
    );
  }

  /// AI 消息更多菜单。
  void _showAssistantMessageMenu(
    ChatProvider chatProvider,
    ChatSession? chat,
    int messageId,
  ) {
    final color = Theme.of(context).colorScheme;
    final msg = chatProvider.currentMessages
        .where((m) => m.isarId == messageId)
        .firstOrNull;
    if (msg == null) return;
    showModalBottomSheetMenu(
      context: context,
      message: msg,
      items: [
        SheetMenuItem(
          icon: const Icon(Icons.edit_outlined),
          label: '编辑',
          onTap: () {
            Navigator.pushNamed(context, AppRoutes.editMessage, arguments: msg);
          },
        ),
        SheetMenuItem(
          icon: const Icon(Icons.copy_outlined),
          label: '复制',
          onTap: () {
            Clipboard.setData(ClipboardData(text: msg.content));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
            );
          },
        ),
        SheetMenuItem(
          icon: Icon(Icons.delete_outline, color: color.error),
          label: '删除',
          onTap: () async {
            final confirmed = await _confirmAction('删除确认', '确定要删除这条消息吗？');
            if (confirmed) chatProvider.deleteMessage(messageId);
          },
        ),
        SheetMenuItem(
          icon: Icon(Icons.delete_forever, color: color.error,),
          label: '删除这条及之后的消息',
          onTap: () async {
            final confirmed = await _confirmAction('删除确认', '将删除此消息及之后的所有消息，是否继续？');
            if (confirmed) chatProvider.deleteMessageAndAfter(messageId);
          },
        ),
      ],
    );
  }

  /// 选择模型弹窗：支持新会话临时选择和已有会话持久化更新。
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
      isDismissible: true,
      enableDrag: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      builder:
          (context) => ModelSelectorBottomSheet(
            allowedModelTypes: const {ModelType.text},
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
