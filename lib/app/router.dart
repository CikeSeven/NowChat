import 'package:flutter/material.dart';
import 'package:now_chat/ui/pages/about_page.dart';
import 'package:now_chat/ui/pages/agent_detail_page.dart';
import 'package:now_chat/ui/pages/agent_form_page.dart';
import 'package:now_chat/ui/pages/chat_settings_page.dart';
import 'package:now_chat/ui/pages/default_chat_params_page.dart';
import 'package:now_chat/ui/pages/edit_message_page.dart';
import 'package:now_chat/ui/pages/plugin_page.dart';
import 'package:now_chat/ui/pages/provider_form_page.dart';

import '../core/models/message.dart';
import '../ui/pages/chat_detail_page.dart';
import '../ui/pages/home_page.dart';

/// AppRoutes 类型定义。
class AppRoutes {
  static const home = '/';
  static const chatDetail = '/chat/detail';
  static const chatSettings = '/chat/settings';
  static const defaultChatParams = '/settings/default_chat_params';
  static const about = '/settings/about';
  static const plugin = '/settings/plugin';
  static const agentForm = '/agent/form';
  static const agentDetail = '/agent/detail';
  static const providerForm = '/provider/form';
  static const editMessage = '/edit_message';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case home:
        return MaterialPageRoute(builder: (_) => const HomePage());

      case chatDetail:
        final args = settings.arguments as Map<String, dynamic>?;
        final chatId = args?['chatId'];
        return MaterialPageRoute(
          builder: (_) => ChatDetailPage(chatId: chatId),
        );

      case chatSettings:
        final args = settings.arguments as Map<String, dynamic>?;
        final rawChatId = args?['chatId'];
        final chatId =
            rawChatId is int
                ? rawChatId
                : int.tryParse(rawChatId?.toString() ?? '');
        if (chatId == null) {
          return MaterialPageRoute(
            builder: (_) => const Scaffold(body: Center(child: Text('会话不存在'))),
          );
        }
        return _buildSlideRoute(
          builder: (_) => ChatSettingsPage(chatId: chatId),
        );

      case defaultChatParams:
        return _buildSlideRoute(
          builder: (_) => const DefaultChatParamsPage(),
        );

      case about:
        return _buildSlideRoute(
          builder: (_) => const AboutPage(),
        );

      case plugin:
        return _buildSlideRoute(
          builder: (_) => const PluginPage(),
        );

      case agentForm:
        final args = settings.arguments as Map<String, dynamic>?;
        final agentId = args?['agentId']?.toString();
        return _buildSlideRoute(
          builder: (_) => AgentFormPage(agentId: agentId),
        );

      case agentDetail:
        final args = settings.arguments as Map<String, dynamic>?;
        final agentId = args?['agentId']?.toString();
        if (agentId == null || agentId.trim().isEmpty) {
          return MaterialPageRoute(
            builder: (_) => const Scaffold(body: Center(child: Text('智能体不存在'))),
          );
        }
        return _buildSlideRoute(
          builder: (_) => AgentDetailPage(agentId: agentId),
        );

      case providerForm:
        final args = settings.arguments as Map<String, dynamic>?;
        final providerId = args?['providerId'] as String?;
        return _buildSlideRoute(
          builder: (_) => ProviderFormPage(providerId: providerId),
        );

      case editMessage:
        // 直接传 Message 对象，不用拆 Map
        final message = settings.arguments as Message?;
        if (message == null) {
          return MaterialPageRoute(
            builder: (_) => const Scaffold(body: Center(child: Text('消息不存在'))),
          );
        }
        return _buildSlideRoute(
          builder: (_) => EditMessagePage(message: message),
        );

      default:
        return MaterialPageRoute(
          builder:
              (_) => const Scaffold(body: Center(child: Text('404 页面未找到'))),
        );
    }
  }

  static Route<T> _buildSlideRoute<T>({required WidgetBuilder builder}) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1), // 从底部进入
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          ),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }
}
