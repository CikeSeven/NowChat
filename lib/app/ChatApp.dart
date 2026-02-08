import 'package:flutter/material.dart';
import 'package:now_chat/app/router.dart';
import 'package:now_chat/app/theme.dart';
import 'package:now_chat/providers/settings_provider.dart';
import 'package:provider/provider.dart';



class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = MaterialTheme(Typography.tall2021);
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: "Now Chat",
          theme: theme.light(),
          darkTheme: theme.dark(),
          themeMode: settings.themeMode,
          onGenerateRoute: AppRoutes.generateRoute,
          initialRoute: AppRoutes.home,
        );
      },
    );
  }
}