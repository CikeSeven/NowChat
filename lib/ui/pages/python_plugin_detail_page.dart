import 'package:flutter/material.dart';
import 'package:now_chat/core/models/python_plugin_manifest.dart';
import 'package:now_chat/providers/python_plugin_provider.dart';
import 'package:provider/provider.dart';

/// Python 插件详情页：展示状态、可选库列表与代码执行区域。
class PythonPluginDetailPage extends StatefulWidget {
  const PythonPluginDetailPage({super.key});

  @override
  State<PythonPluginDetailPage> createState() => _PythonPluginDetailPageState();
}

class _PythonPluginDetailPageState extends State<PythonPluginDetailPage> {
  static const List<String> _baseRuntimeLibraryIds = <String>[
    'libcxx',
    'libgfortran',
    'openblas',
    'numpy',
    'pandas',
  ];

  final TextEditingController _codeController = TextEditingController(
    text: "print('Hello from Now Chat Python plugin!')",
  );

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
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

  String _formatSizeBytes(int? sizeBytes) {
    if (sizeBytes == null || sizeBytes <= 0) return '未知';
    final kb = sizeBytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }

  String _buildBundleSizeText(List<PythonPluginPackage> libraries) {
    final known = libraries.where((item) => (item.sizeBytes ?? 0) > 0).toList();
    if (known.isEmpty) return '大小：未知';
    final total = known.fold<int>(0, (sum, item) => sum + (item.sizeBytes ?? 0));
    return '大小：${_formatSizeBytes(total)}';
  }

  bool _isBundleInstalled(
    PythonPluginProvider provider,
    List<PythonPluginPackage> bundleLibraries,
  ) {
    if (bundleLibraries.isEmpty) return false;
    for (final library in bundleLibraries) {
      final installed = provider.installedLibraries.any(
        (item) => item.id == library.id,
      );
      if (!installed) return false;
    }
    return true;
  }

  Future<void> _installBaseBundle(
    PythonPluginProvider provider,
    List<PythonPluginPackage> bundleLibraries,
  ) async {
    for (final library in bundleLibraries) {
      await provider.installLibrary(library.id);
      if ((provider.lastError ?? '').trim().isNotEmpty) {
        break;
      }
    }
  }

  Future<void> _uninstallBaseBundle(
    PythonPluginProvider provider,
    List<PythonPluginPackage> bundleLibraries,
  ) async {
    final reversed = bundleLibraries.reversed.toList();
    for (final library in reversed) {
      await provider.uninstallLibrary(library.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final provider = context.watch<PythonPluginProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Python 插件')),
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
                          _buildSectionTitle(context, '运行时状态'),
                          Text(
                            '核心版本：${provider.coreVersion ?? 'chaquopy-embedded'}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: color.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed:
                                provider.isBusy
                                    ? null
                                    : () => provider.refreshManifest(),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('刷新包列表'),
                          ),
                          if (provider.isRefreshingManifest) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '正在获取列表...',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: color.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (provider.isBusy) ...[
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value:
                                  !provider.isRefreshingManifest &&
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
                              '正在加载包列表，请稍后刷新',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: color.onSurfaceVariant,
                              ),
                            )
                          else if (provider.manifest!.libraries.isEmpty)
                            Text(
                              '当前没有可安装库包',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: color.onSurfaceVariant,
                              ),
                            )
                          else
                            ...() {
                              final libraries = provider.manifest!.libraries;
                              final byId = <String, PythonPluginPackage>{
                                for (final item in libraries) item.id: item,
                              };

                              final baseBundleLibraries = <PythonPluginPackage>[
                                for (final id in _baseRuntimeLibraryIds)
                                  if (byId[id] != null) byId[id]!,
                              ];
                              final hiddenIds = baseBundleLibraries
                                  .map((item) => item.id)
                                  .toSet();
                              final remainingLibraries = libraries
                                  .where((item) => !hiddenIds.contains(item.id))
                                  .toList();

                              final tiles = <Widget>[];
                              if (baseBundleLibraries.isNotEmpty) {
                                final bundleInstalled = _isBundleInstalled(
                                  provider,
                                  baseBundleLibraries,
                                );
                                tiles.add(
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      8,
                                      10,
                                      8,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: color.outlineVariant.withAlpha(
                                          140,
                                        ),
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
                                                'Python基础库',
                                                style: TextStyle(
                                                  fontSize: 13.5,
                                                  color: color.onSurface,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Text(
                                                '包含 NumPy / Pandas 及其原生依赖',
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  color: color.onSurfaceVariant,
                                                ),
                                              ),
                                              Text(
                                                _buildBundleSizeText(
                                                  baseBundleLibraries,
                                                ),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: color.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        bundleInstalled
                                            ? OutlinedButton(
                                              onPressed:
                                                  provider.isBusy
                                                      ? null
                                                      : () async {
                                                        await _uninstallBaseBundle(
                                                          provider,
                                                          baseBundleLibraries,
                                                        );
                                                      },
                                              child: const Text('卸载'),
                                            )
                                            : FilledButton(
                                              onPressed:
                                                  provider.isBusy
                                                      ? null
                                                      : () async {
                                                        await _installBaseBundle(
                                                          provider,
                                                          baseBundleLibraries,
                                                        );
                                                      },
                                              child: const Text('安装'),
                                            ),
                                      ],
                                    ),
                                  ),
                                );
                              }

                              for (final library in remainingLibraries) {
                                final installed = provider.installedLibraries
                                    .any((item) => item.id == library.id);
                                tiles.add(
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      8,
                                      10,
                                      8,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: color.outlineVariant.withAlpha(
                                          140,
                                        ),
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
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 2,
                                                      ),
                                                  child: Text(
                                                    library.description,
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      color:
                                                          color.onSurfaceVariant,
                                                    ),
                                                  ),
                                                ),
                                              Text(
                                                '大小：${_formatSizeBytes(library.sizeBytes)}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: color.onSurfaceVariant,
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
                                                      : () async {
                                                        await provider
                                                            .uninstallLibrary(
                                                              library.id,
                                                            );
                                                      },
                                              child: const Text('卸载'),
                                            )
                                            : FilledButton(
                                              onPressed:
                                                  provider.isBusy
                                                      ? null
                                                      : () async {
                                                        await provider
                                                            .installLibrary(
                                                              library.id,
                                                            );
                                                      },
                                              child: const Text('安装'),
                                            ),
                                      ],
                                    ),
                                  ),
                                );
                              }

                              return tiles;
                            }(),
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
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                              hintText: '输入 Python 代码',
                              helperText: '已启用执行环境',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              FilledButton.icon(
                                onPressed:
                                    !provider.isExecuting &&
                                            !provider.isRefreshingManifest
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
                                    provider.isExecuting ||
                                            provider.isRefreshingManifest
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
