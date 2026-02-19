import 'package:flutter/material.dart';
import 'package:now_chat/app/router.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:now_chat/ui/widgets/api_provider_card.dart';
import 'package:provider/provider.dart';

/// ApiPage 页面。
class ApiPage extends StatefulWidget {
  const ApiPage({super.key});

  @override
  State<ApiPage> createState() => _ApiPageState();
}

/// _ApiPageState 视图状态。
class _ApiPageState extends State<ApiPage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expandedProviderIds = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleProviderExpanded(String providerId) {
    setState(() {
      if (_expandedProviderIds.contains(providerId)) {
        _expandedProviderIds.remove(providerId);
      } else {
        _expandedProviderIds.add(providerId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final providers = chatProvider.providers;
    final colors = Theme.of(context).colorScheme;
    final query = _searchController.text.trim().toLowerCase();

    final filteredProviders =
        providers.where((provider) {
          final name = provider.name.toLowerCase();
          final type = provider.type.defaultName.toLowerCase();
          final baseUrl = (provider.baseUrl ?? '').toLowerCase();
          final hasRemarkMatch = provider.modelRemarks.values.any(
            (remark) => remark.toLowerCase().contains(query),
          );
          return name.contains(query) ||
              type.contains(query) ||
              baseUrl.contains(query) ||
              hasRemarkMatch;
        }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('API 管理')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索 API 名称、类型或地址',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon:
                    _searchController.text.isEmpty
                        ? null
                        : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child:
                providers.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.hub_outlined,
                            size: 34,
                            color: colors.outline,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '还没有 API 配置',
                            style: TextStyle(
                              fontSize: 15,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '点击右下角添加第一个提供方',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.outline,
                            ),
                          ),
                        ],
                      ),
                    )
                    : filteredProviders.isEmpty
                    ? Center(
                      child: Text(
                        '没有匹配的 API',
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    )
                    : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 90),
                      itemCount: filteredProviders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final provider = filteredProviders[index];
                        final isExpanded = _expandedProviderIds.contains(
                          provider.id,
                        );
                        return ApiProviderCard(
                          key: ValueKey('api-provider-${provider.id}'),
                          provider: provider,
                          isExpanded: isExpanded,
                          onToggleExpand:
                              () => _toggleProviderExpanded(provider.id),
                          onEdit: () {
                            Navigator.pushNamed(
                              context,
                              AppRoutes.providerForm,
                              arguments: {
                                'mode': 'edit',
                                'providerId': provider.id,
                              },
                            );
                          },
                          onDelete:
                              () => _confirmDelete(provider.id, provider.name),
                        );
                      },
                    ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.pushNamed(
            context,
            AppRoutes.providerForm,
            arguments: const {'mode': 'create'},
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('添加 API'),
      ),
    );
  }

  Future<void> _confirmDelete(String providerId, String name) async {
    final color = Theme.of(context).colorScheme;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            backgroundColor: color.surfaceContainerLow,
            title: Text('删除 API', style: TextStyle(color: color.onSurface)),
            content: Text(
              '确认删除 "$name" 吗？该操作不可恢复。',
              style: TextStyle(color: color.onSurfaceVariant),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(
                  '取消',
                  style: TextStyle(color: color.onSurfaceVariant),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text('删除', style: TextStyle(color: color.error)),
              ),
            ],
          ),
    );

    if (shouldDelete == true) {
      if (!mounted) return;
      await context.read<ChatProvider>().deleteProvider(providerId);
    }
  }
}
