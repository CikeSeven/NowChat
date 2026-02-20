import 'package:flutter/material.dart';
import 'package:now_chat/core/update/app_update_models.dart';
import 'package:now_chat/core/update/app_update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// 应用关于页：展示基础信息并提供更新检查入口。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

/// 关于页状态。
class _AboutPageState extends State<AboutPage> {
  static const String _fallbackAppName = 'Now Chat';
  static const String _fallbackVersion = '0.5.3+8';
  static const String _fallbackPackageName = 'com.nowchat';
  static const String _iconAssetPath = 'assets/icon/app_icon.png';
  static const String _projectUrl = 'https://github.com/CikeSeven/NowChat';

  final AppUpdateService _appUpdateService = AppUpdateService();

  String _appName = _fallbackAppName;
  String _version = _fallbackVersion;
  String _packageName = _fallbackPackageName;
  bool _isCheckingUpdate = false;
  String _updateStatusText = '未检查';

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      final appName = info.appName.trim();
      final version = info.version.trim();
      final buildNumber = info.buildNumber.trim();
      final packageName = info.packageName.trim();
      setState(() {
        _appName = appName.isEmpty ? _fallbackAppName : appName;
        _version =
            version.isEmpty
                ? _fallbackVersion
                : (buildNumber.isEmpty ? version : '$version+$buildNumber');
        _packageName =
            packageName.isEmpty ? _fallbackPackageName : packageName;
      });
    } catch (_) {
      // 保持兜底信息，避免界面展示为空。
    }
  }

  /// 检查更新：直连失败后由更新服务自动尝试可用代理。
  Future<void> _checkForUpdate() async {
    if (_isCheckingUpdate) return;
    setState(() {
      _isCheckingUpdate = true;
      _updateStatusText = '检查中...';
    });
    try {
      final result = await _appUpdateService.checkLatestRelease(
        currentVersion: _version,
      );
      if (!mounted) return;

      if (!result.hasUpdate) {
        setState(() {
          _updateStatusText = '已是最新版本';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('当前已是最新版本（${result.latestVersion}）')),
        );
        return;
      }

      setState(() {
        _updateStatusText = '发现新版本 ${result.latestVersion}';
      });
      await _showInstallUpdateDialog(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _updateStatusText = '检查失败';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('检查更新失败：$e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isCheckingUpdate = false;
      });
    }
  }

  /// 发现新版本后，询问用户是否立即安装。
  Future<void> _showInstallUpdateDialog(AppUpdateCheckResult result) async {
    final publishedText =
        result.releaseInfo.publishedAt == null
            ? '-'
            : result.releaseInfo.publishedAt!
                .toLocal()
                .toIso8601String()
                .replaceFirst('T', ' ')
                .split('.')
                .first;

    final shouldInstall = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('发现新版本'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('当前版本：${result.currentVersion}'),
                  Text('最新版本：${result.latestVersion}'),
                  Text('发布时间：$publishedText'),
                  Text('访问通道：${result.usedMirrorName}'),
                  const SizedBox(height: 10),
                  const Text(
                    '更新说明：',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _buildReleaseNotePreview(result.releaseInfo.body),
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('稍后'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('立即安装'),
            ),
          ],
        );
      },
    );

    if (shouldInstall != true || !mounted) return;

    final downloadUrl = result.resolvedDownloadUrl.trim();
    if (downloadUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到可安装 APK 资源')),
      );
      return;
    }

    final success = await launchUrl(
      Uri.parse(downloadUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? '已打开下载链接，请完成安装' : '无法打开下载链接',
        ),
      ),
    );
  }

  /// 更新说明仅展示前几行，避免弹窗内容过长影响阅读。
  String _buildReleaseNotePreview(String rawBody) {
    final lines =
        rawBody
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .take(8)
            .toList();
    if (lines.isEmpty) {
      return '暂无更新说明';
    }
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  _iconAssetPath,
                  width: 92,
                  height: 92,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _appName,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '版本 $_version',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 22),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  children: [
                    _InfoLine(label: '名称', value: _appName),
                    const SizedBox(height: 10),
                    _InfoLine(label: '版本号', value: _version),
                    const SizedBox(height: 10),
                    _InfoLine(label: '包名', value: _packageName),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading:
                    _isCheckingUpdate
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.system_update_alt_rounded),
                title: const Text('检查新版本'),
                subtitle: Text(_updateStatusText),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _isCheckingUpdate ? null : _checkForUpdate,
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.code_outlined),
                title: const Text('项目主页'),
                subtitle: const Text(_projectUrl),
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: () async {
                  final uri = Uri.parse(_projectUrl);
                  final success = await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                  if (!success && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('无法打开项目地址')),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.gavel_outlined),
                title: const Text('开源协议'),
                subtitle: const Text('查看第三方依赖与许可证'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  showLicensePage(
                    context: context,
                    applicationName: _appName,
                    applicationVersion: _version,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 信息行组件。
class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
          ),
        ),
        Text(
          '：',
          style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
