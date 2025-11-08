import 'package:flutter/material.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:provider/provider.dart';

class EditMessagePage extends StatefulWidget {
  final String content;
  const EditMessagePage({super.key, required this.content});

  @override
  State<EditMessagePage> createState() => _EditMessagePageState();
}

class _EditMessagePageState extends State<EditMessagePage> {

  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }


  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {

    _controller.text = widget.content;

    final chatProvider = context.watch<ChatProvider>();
    final color = Theme.of(context).colorScheme;
    
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.close, color: color.primary),
                    onPressed: () => Navigator.of(context).pop(), // 取消，不返回数据
                  ),
                  Text(
                    "编辑API信息",
                    style: TextStyle(fontSize: 16),
                  ),
                  IconButton(
                    icon: Icon(Icons.check, color: color.primary),
                    onPressed: () {},
                  ),
                ],
              ),
            ),

            TextField(
              controller: _controller,
            )
          ],
        )
      ),
    );
  }
}