import 'package:flutter/material.dart';
import 'package:now_chat/providers/python_plugin_provider.dart';
import 'package:provider/provider.dart';

class PluginPage extends StatefulWidget {
  const PluginPage({super.key});

  @override
  State<PluginPage> createState() => _PluginPageState();
}

class _PluginPageState extends State<PluginPage> {
  final TextEditingController _manifestController = TextEditingController();
  final TextEditingController _codeController = TextEditingController(
    text: "print('Hello from Now Chat Python plugin!')",
  );
  bool _syncedManifest = false;

  @override
  void dispose() {
    _manifestController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Color _stateColor(BuildContext context, PythonPluginInstallState state) {
    final color = Theme.of(context).colorScheme;
    switch (state) {
      case PythonPluginInstallState.notInstalled:
        return color.outline;
      case PythonPluginInstallState.downloading:
      case PythonPluginInstallState.installing:
        return color.primary;
      case PythonPluginInstallState.ready:
        return Colors.green;
      case PythonPluginInstallState.broken:
        return color.error;
    }
  }

  String _stateText(PythonPluginInstallState state) {
    switch (state) {
      case PythonPluginInstallState.notInstalled:
        return '未安装';
      case PythonPluginInstallState.downloading:
        return '下载中';
      case PythonPluginInstallState.installing:
        return '安装中';
      case PythonPluginInstallState.ready:
        return '可用';
      case PythonPluginInstallState.broken:
        return '异常';
    }
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final color = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: color.onSurface,
        ),
      ),
    );
  }

  Future<void> _refreshManifest(PythonPluginProvider provider) async {
    await provider.setManifestUrl(_manifestController.text.trim());
    await provider.refreshManifest();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final provider = context.watch<PythonPluginProvider>();
    if (!_syncedManifest && provider.isInitialized) {
      _syncedManifest = true;
      _manifestController.text = provider.manifestUrl;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('插件')),
      body:
          !provider.isInitialized
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle(context, 'Python 运行时状态'),
                          Row(
                            children: [
                              Text(
                                '核心插件：',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: color.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                _stateText(provider.installState),
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: _stateColor(
                                    context,
                                    provider.installState,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if ((provider.coreVersion ?? '').isNotEmpty)
                                Text(
                                  'v${provider.coreVersion}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: color.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                          if (provider.isBusy) ...[
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value:
                                  provider.downloadProgress > 0 &&
                                          provider.downloadProgress <= 1
                                      ? provider.downloadProgress
                                      : null,
                            ),
                          ],
                          if ((provider.lastError ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              provider.lastError!,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: color.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            '默认不内置 Python，按需下载安装核心包，保持主应用轻量。',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: color.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle(context, '插件清单地址'),
                          TextField(
                            controller: _manifestController,
                            minLines: 1,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                              hintText: '输入插件清单 URL',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed:
                                    provider.isBusy
                                        ? null
                                        : () => _refreshManifest(provider),
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('刷新清单'),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed:
                                    provider.isBusy
                                        ? null
                                        : () async {
                                          await provider.setManifestUrl(
                                            _manifestController.text.trim(),
                                          );
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text('清单地址已保存'),
                                            ),
                                          );
                                        },
                                child: const Text('仅保存地址'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle(context, '核心包'),
                          Text(
                            provider.hasManifest
                                ? '清单核心版本：${provider.manifest!.core.version}'
                                : '请先刷新清单',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: color.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed:
                                    provider.isBusy
                                        ? null
                                        : () => provider.installCore(),
                                icon: const Icon(Icons.download_rounded),
                                label: Text(
                                  provider.hasCoreUpdate
                                      ? '更新核心包'
                                      : '安装核心包',
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed:
                                    provider.isBusy || provider.coreVersion == null
                                        ? null
                                        : () => provider.uninstallCore(),
                                icon: const Icon(Icons.delete_outline_rounded),
                                label: const Text('卸载核心包'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle(context, '可选基础库包'),
                          if (!provider.hasManifest)
                            Text(
                              '请先刷新清单后再安装库包',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: color.onSurfaceVariant,
                              ),
                            )
                          else if (provider.manifest!.libraries.isEmpty)
                            Text(
                              '当前清单没有可安装库包',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: color.onSurfaceVariant,
                              ),
                            )
                          else
                            ...provider.manifest!.libraries.map((library) {
                              final installed = provider.installedLibraries
                                  .any((item) => item.id == library.id);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: color.outlineVariant.withAlpha(140),
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${library.name} (${library.version})',
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              color: color.onSurface,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (library.description.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 2,
                                              ),
                                              child: Text(
                                                library.description,
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  color: color.onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    installed
                                        ? OutlinedButton(
                                          onPressed:
                                              provider.isBusy
                                                  ? null
                                                  : () => provider
                                                      .uninstallLibrary(
                                                        library.id,
                                                      ),
                                          child: const Text('卸载'),
                                        )
                                        : FilledButton(
                                          onPressed:
                                              provider.isBusy
                                                  ? null
                                                  : () => provider
                                                      .installLibrary(
                                                        library.id,
                                                      ),
                                          child: const Text('安装'),
                                        ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle(context, '执行 Python 代码'),
                          TextField(
                            controller: _codeController,
                            minLines: 6,
                            maxLines: 12,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              isDense: true,
                              hintText: '输入 Python 代码',
                              helperText:
                                  provider.isCoreReady
                                      ? '已启用执行'
                                      : '请先安装核心包后执行',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              FilledButton.icon(
                                onPressed:
                                    provider.isCoreReady && !provider.isExecuting
                                        ? () => provider.executeCode(
                                          _codeController.text,
                                        )
                                        : null,
                                icon: Icon(
                                  provider.isExecuting
                                      ? Icons.hourglass_top_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                                label: Text(
                                  provider.isExecuting ? '执行中...' : '运行代码',
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed:
                                    provider.isExecuting
                                        ? null
                                        : () => provider.clearExecutionResult(),
                                child: const Text('清空输出'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                            decoration: BoxDecoration(
                              color: color.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: color.outlineVariant.withAlpha(120),
                              ),
                            ),
                            child: Builder(
                              builder: (context) {
                                final result = provider.lastExecutionResult;
                                if (result == null) {
                                  return Text(
                                    '暂无执行结果',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: color.onSurfaceVariant,
                                    ),
                                  );
                                }
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'exitCode=${result.exitCode} · ${result.duration.inMilliseconds}ms${result.timedOut ? ' · timeout' : ''}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: color.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    SelectableText(
                                      result.stdout.trim().isEmpty
                                          ? '(stdout 为空)'
                                          : result.stdout,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        height: 1.4,
                                        color: color.onSurface,
                                      ),
                                    ),
                                    if (result.stderr.trim().isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      SelectableText(
                                        result.stderr,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          height: 1.4,
                                          color: color.error,
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
    );
  }
}
