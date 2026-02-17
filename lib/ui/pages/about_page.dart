import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// 应用关于页，展示应用信息并提供开源协议入口。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static const String _fallbackAppName = 'Now Chat';
  static const String _fallbackVersion = '0.3.1+4';
  static const String _fallbackPackageName = 'com.nowchat';
  static const String _iconAssetPath = 'assets/icon/app_icon.png';
  static const String _projectUrl = 'https://github.com/CikeSeven/NowChat';

  String _appName = _fallbackAppName;
  String _version = _fallbackVersion;
  String _packageName = _fallbackPackageName;

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
