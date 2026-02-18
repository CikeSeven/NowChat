import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:now_chat/app/ChatApp.dart';
import 'package:now_chat/providers/agent_provider.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:now_chat/providers/python_plugin_provider.dart';
import 'package:now_chat/providers/settings_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'core/models/chat_session.dart';
import 'core/models/message.dart';


Future<Isar> _openIsar() async {
  final dir = await getApplicationDocumentsDirectory();
  return await Isar.open(
    [MessageSchema, ChatSessionSchema],
    directory: dir.path,
  );
}
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final isar = await _openIsar();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatProvider(isar)),
        ChangeNotifierProvider(create: (_) => AgentProvider(isar)),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => PythonPluginProvider()),
      ],
      child: const ChatApp(),
    ),
  );
}
