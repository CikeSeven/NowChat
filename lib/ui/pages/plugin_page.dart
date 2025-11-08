import 'package:flutter/material.dart';

class PluginPage extends StatelessWidget {
  const PluginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('插件')),
      body: Center(
        child: Text("Plugin Page"),
      ),
    );
  }
}