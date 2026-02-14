import 'package:flutter/material.dart';
import 'package:now_chat/core/models/message.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:provider/provider.dart';

class EditMessagePage extends StatefulWidget {
  final Message message;
  const EditMessagePage({super.key, required this.message});

  @override
  State<EditMessagePage> createState() => _EditMessagePageState();
}

class _EditMessagePageState extends State<EditMessagePage> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.message.content);
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _saveMessage() async {
    final newContent = _controller.text.trim();
    if (newContent.isEmpty) return;
    final updatedMessage = widget.message..content = newContent;
    final chatProvider = context.read<ChatProvider>();
    await chatProvider.saveMessage(updatedMessage);
    if (!mounted) return;
    Navigator.of(context).pop(updatedMessage);
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("编辑消息"),
        leading: IconButton(
          icon: Icon(Icons.close, color: color.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.check, color: _controller.text.trim().isEmpty ? color.onSurface.withAlpha(120) : color.primary),
            onPressed: _controller.text.trim().isEmpty ? null : _saveMessage,
          )
        ],
        backgroundColor: color.surface,
        elevation: 1,
      ),
      body: Column(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              expands: true,         // 占满父容器
              maxLines: null,        // 必须设置为 null
              minLines: null,        // 必须设置为 null
              decoration: const InputDecoration(
                border: InputBorder.none, // 去掉边框
                contentPadding: EdgeInsets.only(left: 16, right: 16, bottom: 8),
              ),
              style: const TextStyle(fontSize: 16),
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
            ),
          ),
        ],
      ),
    );
  }
}
