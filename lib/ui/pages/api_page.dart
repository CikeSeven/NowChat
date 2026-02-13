import 'package:flutter/material.dart';
import 'package:now_chat/app/router.dart';
import 'package:now_chat/core/models/ai_provider_config.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:provider/provider.dart';

class ApiPage extends StatefulWidget {
  const ApiPage({super.key});

  @override
  State<ApiPage> createState() => _ApiPageState();
}

class _ApiPageState extends State<ApiPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
                        return _ApiProviderCard(
                          provider: provider,
                          onTap: () {
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

class _ApiProviderCard extends StatelessWidget {
  final AIProviderConfig provider;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ApiProviderCard({
    required this.provider,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final models = provider.models;
    final previewModels = models.take(3).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Card(
        elevation: 0,
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        provider.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                      icon: Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: colors.error,
                      ),
                      onPressed: onDelete,
                    ),
                  ],
                ),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    _buildTag(context, provider.type.defaultName),
                    _buildTag(context, '${models.length} 个模型'),
                  ],
                ),
                const SizedBox(height: 5),
                Tooltip(
                  message: provider.baseUrl ?? '',
                  child: Text(
                    provider.baseUrl ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (previewModels.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children:
                        previewModels
                            .map(
                              (model) => ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.4,
                                ),
                                child: Builder(
                                  builder: (context) {
                                    final features = provider.featuresForModel(
                                      model,
                                    );
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        color: colors.surface,
                                        border: Border.all(
                                          color: colors.outline.withAlpha(100),
                                        ),
                                      ),
                                      child: Tooltip(
                                        message:
                                            '${provider.displayNameForModel(model)}\n$model',
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                provider.displayNameForModel(
                                                  model,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      colors.onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                            if (features.hasAnyCapability)
                                              const SizedBox(width: 4),
                                            if (features.supportsVision)
                                              Tooltip(
                                                message: '支持视觉',
                                                child: Icon(
                                                  Icons.visibility_outlined,
                                                  size: 12,
                                                  color: colors.outline,
                                                ),
                                              ),
                                            if (features.supportsVision &&
                                                features.supportsTools)
                                              const SizedBox(width: 2),
                                            if (features.supportsTools)
                                              Tooltip(
                                                message: '支持工具',
                                                child: Icon(
                                                  Icons.build_outlined,
                                                  size: 12,
                                                  color: colors.outline,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTag(BuildContext context, String text) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withAlpha(125),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: colors.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
