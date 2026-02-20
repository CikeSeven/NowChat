import 'package:flutter/material.dart';
import 'package:now_chat/app/router.dart';
import 'package:now_chat/providers/plugin_provider.dart';
import 'package:provider/provider.dart';

/// 应用启动加载页：等待插件系统初始化完成后再进入主页。
class StartupLoadingPage extends StatefulWidget {
  const StartupLoadingPage({super.key});

  @override
  State<StartupLoadingPage> createState() => _StartupLoadingPageState();
}

class _StartupLoadingPageState extends State<StartupLoadingPage> {
  /// 防止初始化完成后重复跳转首页。
  bool _navigated = false;

  /// 当插件系统完成初始化后执行一次性跳转。
  void _navigateToHomeIfReady(bool isReady) {
    if (!isReady || _navigated) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _navigated) return;
      _navigated = true;
      Navigator.of(context).pushReplacementNamed(AppRoutes.home);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pluginProvider = context.watch<PluginProvider>();
    final isReady = pluginProvider.isInitialized;
    _navigateToHomeIfReady(isReady);

    final loadingText =
        pluginProvider.isRefreshingManifest ? '正在同步插件清单...' : '正在加载应用数据...';

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
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 16),
                Text(
                  loadingText,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if ((pluginProvider.lastError ?? '').trim().isNotEmpty &&
                    !isReady) ...[
                  const SizedBox(height: 12),
                  Text(
                    pluginProvider.lastError!,
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
