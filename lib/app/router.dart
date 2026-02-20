import 'package:flutter/material.dart';
import 'package:now_chat/ui/pages/about_page.dart';
import 'package:now_chat/ui/pages/app_data_management_page.dart';
import 'package:now_chat/ui/pages/agent_detail_page.dart';
import 'package:now_chat/ui/pages/agent_form_page.dart';
import 'package:now_chat/ui/pages/chat_settings_page.dart';
import 'package:now_chat/ui/pages/default_chat_params_page.dart';
import 'package:now_chat/ui/pages/edit_message_page.dart';
import 'package:now_chat/ui/pages/plugin_page.dart';
import 'package:now_chat/ui/pages/provider_form_page.dart';
import 'package:now_chat/ui/pages/startup_loading_page.dart';

import '../core/models/message.dart';
import '../ui/pages/chat_detail_page.dart';
import '../ui/pages/home_page.dart';

/// 全局路由表。
///
/// 约定：
/// - 页面路由统一从此处维护，避免字符串散落在各页面。
/// - `generateRoute` 负责参数解析与兜底，页面本身可假设参数已校验。
class AppRoutes {
  /// 启动加载页（用于应用初始化、预加载本地数据）。
  static const startup = '/startup';

  /// 主页面（底部导航容器）。
  static const home = '/';

  /// 聊天详情页。
  ///
  /// 参数：
  /// - `arguments` 为 `Map<String, dynamic>?`
  /// - 可选键 `chatId`（int 或可转 int 的值）
  static const chatDetail = '/chat/detail';

  /// 会话设置页。
  ///
  /// 参数：
  /// - `arguments` 为 `Map<String, dynamic>?`
  /// - 必填键 `chatId`（int 或可转 int 的值）
  static const chatSettings = '/chat/settings';

  /// 设置 -> 默认对话参数。
  static const defaultChatParams = '/settings/default_chat_params';

  /// 设置 -> 应用数据管理（导入/导出）。
  static const appDataManagement = '/settings/app_data_management';

  /// 设置 -> 关于。
  static const about = '/settings/about';

  /// 设置 -> 插件中心。
  static const plugin = '/settings/plugin';

  /// 工具创建/编辑页。
  ///
  /// 参数：
  /// - `arguments` 为 `Map<String, dynamic>?`
  /// - 可选键 `agentId`
  static const agentForm = '/agent/form';

  /// 工具详情页。
  ///
  /// 参数：
  /// - `arguments` 为 `Map<String, dynamic>?`
  /// - 必填键 `agentId`
  static const agentDetail = '/agent/detail';

  /// API 提供方创建/编辑页。
  ///
  /// 参数：
  /// - `arguments` 为 `Map<String, dynamic>?`
  /// - 可选键 `providerId`
  static const providerForm = '/provider/form';

  /// 消息编辑页。
  ///
  /// 参数：
  /// - `arguments` 为 `Message`
  static const editMessage = '/edit_message';

  /// 路由分发入口。
  ///
  /// 这里统一做参数合法性检查，若参数缺失则返回一个可读的错误页，
  /// 避免空指针异常直接暴露给用户。
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case startup:
        return MaterialPageRoute(builder: (_) => const StartupLoadingPage());

      case home:
        return MaterialPageRoute(builder: (_) => const HomePage());

      case chatDetail:
        // 详情页允许无 chatId（例如从某些入口新建会话后直接进入）。
        final args = settings.arguments as Map<String, dynamic>?;
        final chatId = args?['chatId'];
        return MaterialPageRoute(
          builder: (_) => ChatDetailPage(chatId: chatId),
        );

      case chatSettings:
        // 会话设置必须依赖有效 chatId，因此这里先做安全解析和兜底提示。
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

      case appDataManagement:
        return _buildSlideRoute(
          builder: (_) => const AppDataManagementPage(),
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
        // agentId 为空表示新建；有值表示编辑。
        final args = settings.arguments as Map<String, dynamic>?;
        final agentId = args?['agentId']?.toString();
        return _buildSlideRoute(
          builder: (_) => AgentFormPage(agentId: agentId),
        );

      case agentDetail:
        // 详情页必须有 agentId，否则给出明确提示而不是崩溃。
        final args = settings.arguments as Map<String, dynamic>?;
        final agentId = args?['agentId']?.toString();
        if (agentId == null || agentId.trim().isEmpty) {
          return MaterialPageRoute(
            builder: (_) => const Scaffold(body: Center(child: Text('工具不存在'))),
          );
        }
        return _buildSlideRoute(
          builder: (_) => AgentDetailPage(agentId: agentId),
        );

      case providerForm:
        // providerId 为空表示新建提供方；有值表示编辑既有提供方。
        final args = settings.arguments as Map<String, dynamic>?;
        final providerId = args?['providerId'] as String?;
        return _buildSlideRoute(
          builder: (_) => ProviderFormPage(providerId: providerId),
        );

      case editMessage:
        // 编辑消息页面直接接收 Message 实例，避免重复序列化/反序列化。
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

  /// 统一底部滑入转场。
  ///
  /// 该项目多数“二级设置/编辑页”都采用该动画，保持交互一致性。
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
