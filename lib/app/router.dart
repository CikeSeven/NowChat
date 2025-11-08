import 'package:flutter/material.dart';
import 'package:now_chat/ui/pages/edit_message_page.dart';
import 'package:now_chat/ui/pages/edit_provider_page.dart';

import '../core/models/message.dart';
import '../ui/pages/chat_detail_page.dart';
import '../ui/pages/home_page.dart';

class AppRoutes {
  static const home = '/';
  static const chatDetail = '/chat/detail';
  static const editProvider = '/edit_provider';
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
        
      case editProvider:
        final args = settings.arguments as Map<String, dynamic>?;
        final providerId = args?['providerId'];
        return _buildSlideRoute(
          builder: (_) => EditProviderPage(providerId: providerId,)
        );
      
      case editMessage:
        // 直接传 Message 对象，不用拆 Map
        final message = settings.arguments as Message?;
        if (message == null) {
          return MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: Center(child: Text('消息不存在')),
            ),
          );
        }
        return _buildSlideRoute(
          builder: (_) => EditMessagePage(message: message),
        );


      default:
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text('404 页面未找到')),
          ),
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