import 'dart:async';

import 'package:flutter/material.dart';
import 'package:now_chat/app/router.dart';
import 'package:now_chat/core/plugin/plugin_hook_bus.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:now_chat/providers/plugin_provider.dart';
import 'package:now_chat/util/app_logger.dart';
import 'package:provider/provider.dart';

/// 启动加载阶段。
enum _StartupStage {
  loadingPlugins,
  loadingAppData,
}

/// 应用启动加载页：先加载本地插件，再加载应用数据，最后进入主页。
class StartupLoadingPage extends StatefulWidget {
  const StartupLoadingPage({super.key});

  @override
  State<StartupLoadingPage> createState() => _StartupLoadingPageState();
}

class _StartupLoadingPageState extends State<StartupLoadingPage> {
  /// 防止启动流程重复执行。
  bool _isBootstrapping = false;

  /// 防止完成后重复跳转首页。
  bool _navigated = false;

  /// 当前启动阶段文案状态。
  _StartupStage _stage = _StartupStage.loadingPlugins;

  /// 启动阶段出现的致命错误（用于页面兜底展示）。
  String? _fatalError;

  @override
  void initState() {
    super.initState();
    // 等首帧构建完成后再启动异步初始化，避免在 build 期间触发 Provider 通知。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_bootstrap());
    });
  }

  /// 串行启动流程：
  /// 1. 先加载本地插件并注册工具/Hook。
  /// 2. 再加载会话/API（应用数据），并触发数据加载前后 Hook。
  /// 3. 进入主页后后台刷新插件市场。
  Future<void> _bootstrap() async {
    if (_isBootstrapping || _navigated) return;
    _isBootstrapping = true;
    final chatProvider = context.read<ChatProvider>();
    final pluginProvider = context.read<PluginProvider>();

    try {
      AppLogger.i('启动流程[1/3] 开始加载本地插件（工具/Hook）');
      await pluginProvider.ensureInitialized();
      AppLogger.i(
        '启动流程[1/3] 本地插件加载完成: local=${pluginProvider.localPluginCount}, installed=${pluginProvider.installedPluginCount}',
      );
      AppLogger.i('启动流程[2/3] 触发 app_data_before_load Hook');
      await PluginHookBus.emit(
        'app_data_before_load',
        payload: <String, dynamic>{
          'source': 'startup',
        },
      );

      if (!mounted) return;
      setState(() {
        _stage = _StartupStage.loadingAppData;
      });

      AppLogger.i('启动流程[2/3] 开始加载应用数据（API/会话）');
      await chatProvider.ensureInitialized();
      AppLogger.i(
        '启动流程[2/3] 应用数据加载完成: chats=${chatProvider.chatList.length}, providers=${chatProvider.providers.length}',
      );
      AppLogger.i('启动流程[2/3] 触发 app_data_after_load Hook');
      await PluginHookBus.emit(
        'app_data_after_load',
        payload: <String, dynamic>{
          'source': 'startup',
          'chatCount': chatProvider.chatList.length,
          'providerCount': chatProvider.providers.length,
        },
      );

      AppLogger.i('启动流程[3/3] 进入应用并后台刷新插件市场');
      pluginProvider.startBackgroundManifestRefresh();
      if (!mounted || _navigated) return;
      _navigated = true;
      Navigator.of(context).pushReplacementNamed(AppRoutes.home);
    } catch (e, st) {
      AppLogger.e('启动流程失败', e, st);
      if (!mounted) return;
      setState(() {
        _fatalError = '启动失败: $e';
      });
    } finally {
      _isBootstrapping = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loadingText =
        _stage == _StartupStage.loadingPlugins
            ? '正在加载插件...'
            : '正在加载应用数据...';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(strokeWidth: 4),
                ),
                const SizedBox(height: 16),
                Text(
                  loadingText,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if ((_fatalError ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    _fatalError!,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
