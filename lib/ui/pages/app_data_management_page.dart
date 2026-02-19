import 'package:flutter/material.dart';
import 'package:now_chat/core/repository/app_data_transfer_service.dart';
import 'package:now_chat/providers/agent_provider.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:provider/provider.dart';

/// 应用数据管理页：导入/导出会话、工具（智能体）和 API 配置。
class AppDataManagementPage extends StatefulWidget {
  const AppDataManagementPage({super.key});

  @override
  State<AppDataManagementPage> createState() => _AppDataManagementPageState();
}

class _AppDataManagementPageState extends State<AppDataManagementPage> {
  bool _includeApiKeys = false;
  bool _isExporting = false;
  bool _isImporting = false;

  /// 导出应用数据到用户选择的文件。
  Future<void> _exportData() async {
    if (_isExporting || _isImporting) return;
    setState(() {
      _isExporting = true;
    });
    try {
      final service = AppDataTransferService(
        isar: context.read<ChatProvider>().isar,
      );
      final path = await service.exportBackupToUserSelectedFile(
        includeApiKeys: _includeApiKeys,
      );
      if (!mounted) return;
      if (path == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已取消导出')));
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出成功：$path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败：$e')));
    } finally {
      if (!mounted) return;
      setState(() {
        _isExporting = false;
      });
    }
  }

  /// 导入前二次确认（导入会清空后覆盖）。
  Future<bool> _confirmImport() async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('确认导入'),
            content: const Text(
              '导入会先清空当前会话、工具（智能体）和 API 配置，然后使用备份数据覆盖。插件数据不会导入。是否继续？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('继续导入'),
              ),
            ],
          ),
    );
    return ok == true;
  }

  /// 从文件导入数据并刷新 Provider 状态。
  Future<void> _importData() async {
    if (_isExporting || _isImporting) return;
    final confirmed = await _confirmImport();
    if (!confirmed || !mounted) return;

    setState(() {
      _isImporting = true;
    });
    try {
      final chatProvider = context.read<ChatProvider>();
      final agentProvider = context.read<AgentProvider>();
      final service = AppDataTransferService(isar: chatProvider.isar);
      final importedName = await service.importFromUserSelectedFileAndReplaceAll();
      if (!mounted) return;
      if (importedName == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已取消导入')));
        return;
      }

      await chatProvider.reloadFromStorage();
      await agentProvider.reloadFromStorage();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入成功：$importedName')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入失败：$e')));
    } finally {
      if (!mounted) return;
      setState(() {
        _isImporting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _isExporting || _isImporting;
    return Scaffold(
      appBar: AppBar(title: const Text('应用数据管理')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '导出数据',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '导出会话、工具（智能体）和 API 配置。暂不包含插件数据。',
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('导出时包含 API key'),
                    value: _includeApiKeys,
                    onChanged:
                        isBusy
                            ? null
                            : (value) {
                              setState(() {
                                _includeApiKeys = value;
                              });
                            },
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: isBusy ? null : _exportData,
                      icon:
                          _isExporting
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                              : const Icon(Icons.ios_share_rounded),
                      label: Text(_isExporting ? '导出中...' : '导出数据'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '导入数据',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '从备份文件导入会话、工具（智能体）和 API 配置。导入会执行清空覆盖；备份里包含的 API key 会直接导入。',
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '注意：导入会清空当前会话、工具和 API 配置，且无法撤销。',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: isBusy ? null : _importData,
                      icon:
                          _isImporting
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                              : const Icon(Icons.upload_file_rounded),
                      label: Text(_isImporting ? '导入中...' : '导入数据'),
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
