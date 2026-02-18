import 'package:flutter/material.dart';
import 'package:now_chat/core/models/chat_session.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:now_chat/providers/settings_provider.dart';
import 'package:provider/provider.dart';

class ChatSettingsPage extends StatefulWidget {
  final int chatId;

  const ChatSettingsPage({super.key, required this.chatId});

  @override
  State<ChatSettingsPage> createState() => _ChatSettingsPageState();
}

class _ChatSettingsPageState extends State<ChatSettingsPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _maxTokensController = TextEditingController();
  final TextEditingController _maxConversationTurnsController =
      TextEditingController();
  final TextEditingController _systemPromptController = TextEditingController();

  bool _initialized = false;
  ChatSession? _chat;

  double _temperature = 0.7;
  double _topP = 1.0;
  bool _isStreaming = true;
  bool _useMaxTokens = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final chatProvider = context.read<ChatProvider>();
    final chat = chatProvider.getChatById(widget.chatId);
    _chat = chat;
    if (chat != null) {
      _titleController.text = chat.title;
      _temperature = chat.temperature;
      _topP = chat.topP;
      _isStreaming = chat.isStreaming;
      _useMaxTokens = chat.maxTokens > 0 && chat.maxTokens != 4096;
      _maxTokensController.text =
          _useMaxTokens ? chat.maxTokens.toString() : SettingsProvider.defaultMaxTokensValue.toString();
      _maxConversationTurnsController.text = chat.maxConversationTurns
          .toString();
      _systemPromptController.text = chat.systemPrompt ?? '';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _maxTokensController.dispose();
    _maxConversationTurnsController.dispose();
    _systemPromptController.dispose();
    super.dispose();
  }

  int? get _maxTokens {
    final value = int.tryParse(_maxTokensController.text.trim());
    if (value == null || value <= 0) return null;
    return value;
  }

  int? get _maxConversationTurns {
    final value = int.tryParse(_maxConversationTurnsController.text.trim());
    if (value == null || value <= 0) return null;
    return value;
  }

  bool get _canSave =>
      _chat != null &&
      (!_useMaxTokens || _maxTokens != null) &&
      _maxConversationTurns != null &&
      _titleController.text.trim().isNotEmpty;

  Future<void> _save() async {
    final chat = _chat;
    final maxTokens = _useMaxTokens ? _maxTokens : 0;
    final maxConversationTurns = _maxConversationTurns;
    if (chat == null || maxTokens == null || maxConversationTurns == null) {
      return;
    }
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final systemPrompt = _systemPromptController.text.trim();

    final chatProvider = context.read<ChatProvider>();
    final provider =
        chat.providerId == null
            ? null
            : chatProvider.getProviderById(chat.providerId!);
    final streamingSupported = provider?.requestMode.supportsStreaming ?? true;

    if (title != chat.title) {
      await chatProvider.renameChat(chat.id, title);
    }
    await chatProvider.updateChat(
      chat,
      systemPrompt: systemPrompt,
      temperature: _temperature,
      topP: _topP,
      maxTokens: maxTokens,
      maxConversationTurns: maxConversationTurns,
      isStreaming: streamingSupported ? _isStreaming : false,
      lastUpdated: DateTime.now(),
    );

    if (!mounted) return;
    Navigator.of(
      context,
    ).pop({'saved': true, 'chatId': chat.id, 'systemPrompt': systemPrompt});
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final chatProvider = context.watch<ChatProvider>();
    final chat = chatProvider.getChatById(widget.chatId) ?? _chat;

    if (chat == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('会话设置')),
        body: const Center(child: Text('会话不存在')),
      );
    }

    final provider =
        chat.providerId == null
            ? null
            : chatProvider.getProviderById(chat.providerId!);
    final providerName = provider?.name ?? '未选择';
    final modelName = chat.model ?? '未选择';
    final streamingSupported = provider?.requestMode.supportsStreaming ?? true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('会话设置'),
        actions: [
          TextButton(
            onPressed: _canSave ? _save : null,
            child: Text(
              '保存',
              style: TextStyle(
                color:
                    _canSave ? colors.primary : colors.onSurface.withAlpha(120),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前会话',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '会话标题：${chat.title}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: '会话标题',
                      helperText: '保存后立即生效',
                      errorText:
                          _titleController.text.trim().isEmpty
                              ? '标题不能为空'
                              : null,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Provider：$providerName',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '模型：$modelName',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'API 参数',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _systemPromptController,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                      labelText: '人格设置 / System Prompt',
                      hintText: '例如：你是一名严谨的中文技术助手，回答要简洁、可执行。',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '该系统提示会在当前会话的每次请求中作为顶部指令发送，可随时修改。',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildSliderRow(
                    title: 'Temperature',
                    valueText: _temperature.toStringAsFixed(2),
                    child: Slider(
                      min: 0,
                      max: 2,
                      divisions: 40,
                      value: _temperature,
                      onChanged: (value) {
                        setState(() {
                          _temperature = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildSliderRow(
                    title: 'top_p',
                    valueText: _topP.toStringAsFixed(2),
                    child: Slider(
                      min: 0,
                      max: 1,
                      divisions: 40,
                      value: _topP,
                      onChanged: (value) {
                        setState(() {
                          _topP = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('启用最大输出tokens'),
                    subtitle: Text('开启后生成内容超过上限时模型可能提前结束',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    value: _useMaxTokens,
                    onChanged: (value) {
                      setState(() {
                        _useMaxTokens = value;
                        if (_useMaxTokens) {
                          final parsed = int.tryParse(
                            _maxTokensController.text.trim(),
                          );
                          if (parsed == null || parsed <= 0) {
                            _maxTokensController.text = SettingsProvider.defaultMaxTokensValue.toString();
                          }
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _maxTokensController,
                    keyboardType: TextInputType.number,
                    enabled: _useMaxTokens,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'max_tokens',
                      helperText:
                          _useMaxTokens ? '请输入大于 0 的整数（默认 ${SettingsProvider.defaultMaxTokensValue}）' : '当前未启用',
                      errorText:
                          !_useMaxTokens ||
                                  _maxTokensController.text.isEmpty ||
                                  _maxTokens != null
                              ? null
                              : 'max_tokens 无效',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _maxConversationTurnsController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: '最大消息轮次',
                      helperText: '按“用户+AI”算1轮，仅发送最近N轮上下文',
                      errorText:
                          _maxConversationTurnsController.text.isEmpty ||
                                  _maxConversationTurns != null
                              ? null
                              : '轮次无效',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('流式输出'),
                    subtitle: Text(
                      streamingSupported ? '当前请求方式支持流式输出' : '当前请求方式不支持流式输出',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    value: streamingSupported ? _isStreaming : false,
                    onChanged:
                        streamingSupported
                            ? (value) {
                              setState(() {
                                _isStreaming = value;
                              });
                            }
                            : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required String title,
    required String valueText,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontSize: 13)),
            Text(valueText, style: const TextStyle(fontSize: 12)),
          ],
        ),
        child,
      ],
    );
  }
}
