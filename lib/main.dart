import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:now_chat/app/ChatApp.dart';
import 'package:now_chat/providers/agent_provider.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:now_chat/providers/image_generation_queue_provider.dart';
import 'package:now_chat/providers/plugin_provider.dart';
import 'package:now_chat/providers/settings_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'core/models/chat_session.dart';
import 'core/models/message.dart';

/// 打开本地 Isar 数据库。
Future<Isar> _openIsar() async {
  final dir = await getApplicationDocumentsDirectory();
  return await Isar.open([
    MessageSchema,
    ChatSessionSchema,
  ], directory: dir.path);
}

/// 应用启动入口。
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final isar = await _openIsar();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatProvider(isar)),
        ChangeNotifierProvider(create: (_) => AgentProvider(isar)),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProxyProvider<
          SettingsProvider,
          ImageGenerationQueueProvider
        >(
          create: (_) => ImageGenerationQueueProvider(),
          update: (_, settings, queueProvider) {
            final provider = queueProvider ?? ImageGenerationQueueProvider();
            provider.bindSettings(settings);
            return provider;
          },
        ),
        ChangeNotifierProvider(create: (_) => PluginProvider()),
      ],
      child: const ChatApp(),
    ),
  );
}
