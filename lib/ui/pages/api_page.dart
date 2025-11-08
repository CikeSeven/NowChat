import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:now_chat/app/router.dart';
import 'package:now_chat/providers/chat_provider.dart';
import 'package:now_chat/ui/widgets/api_list_item.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/ai_provider_config.dart';

typedef TypeEntry = DropdownMenuEntry<TypeLable>;

enum TypeLable {
  openAI('OpenAI', ProviderType.openai),
  gemini('Gemini', ProviderType.gemini),
  claude('Claude', ProviderType.claude),
  deepseek('DeepSeek', ProviderType.deepseek),
  openaiCompatible('OpenAI兼容', ProviderType.openaiCompatible);

  const TypeLable(this.label, this.type);
  final String label;
  final ProviderType type;

  static final List<TypeEntry> entries = UnmodifiableListView<TypeEntry>(
    values
        .map<TypeEntry>(
          (TypeLable t) => DropdownMenuEntry<TypeLable>(
            value: t,
            label: t.label,
            // 可选：leadingIcon / style 等
          ),
        )
        .toList(),
  );
}

class ApiPage extends StatefulWidget {
  const ApiPage({super.key});
  @override
  State<ApiPage> createState() => _ApiPageState();
}

class _ApiPageState extends State<ApiPage> {
  final TextEditingController _createController = TextEditingController();

  @override
  void dispose() {
    _createController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final providers = chatProvider.providers;
    final color = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: color.surface,
        title: Text(
          'API 管理',
          style: TextStyle(color: color.onSurface),
        ),
      ),
      body: providers.isEmpty
      ? Center(
          child: Text(
            '暂无API',
            style: TextStyle(fontSize: 16, color: color.onSurfaceVariant),
          ),
        )
      : ListView.builder(
          itemCount: providers.length,
          itemBuilder: (context, index) {
            final provider = providers[index];
            return ApiListItem(
              provider: provider,
              onTap: () {
                Navigator.pushNamed(
                  context,
                  AppRoutes.editProvider,
                  arguments: {'providerId': provider.id}
                );
              },
              onDelete: () {
                _confirmDelete(context, provider.id, provider.name);
              },
            );
            
          },
        ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddApiDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }


  // 删除API确认弹窗
  Future<bool?> _confirmDelete(BuildContext context, String providerId, String name) async {
    final color = Theme.of(context).colorScheme;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: color.surfaceContainerLow,
        title: Text('是否删除API', style: TextStyle(color: color.onSurface)),
        content:
            Text('API "$name" 删除后将无法恢复。', style: TextStyle(color: color.onSurfaceVariant)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('取消', style: TextStyle(color: color.onSurfaceVariant))),
          TextButton(
              onPressed: () { 
                final chatProvider = context.read<ChatProvider>();
                chatProvider.deleteProvider(providerId);
                Navigator.pop(context, true);
              },
              child: Text('删除', style: TextStyle(color: color.error))),
        ],
      ),
    );
  }

  // 创建新API弹窗
  void _showAddApiDialog(BuildContext context) {
    final TextEditingController  nameControllerr = TextEditingController();
    final TextEditingController typeController = TextEditingController();
    TypeLable? selectedType = TypeLable.openAI;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final apiKey = nameControllerr.text.trim();
            final isFormValid = apiKey.isNotEmpty && selectedType != null;
            final chatProvider = context.read<ChatProvider>();

            return AlertDialog(
              title: const Text('添加 API'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameControllerr,
                      autofocus: true,
                      onChanged: (value) => setState(() {}), // 触发按钮状态更新
                      decoration: InputDecoration(
                        labelText: 'API名称',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text("API类型"),
                        SizedBox(width: 16,),
                        Expanded(
                          child: DropdownMenu<TypeLable>(
                            initialSelection: TypeLable.openAI,
                            dropdownMenuEntries: TypeLable.entries,
                            controller: typeController,
                            onSelected: (TypeLable? type) {
                              setState(() {
                                selectedType = type;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: isFormValid
                      ? () {
                          final ProviderType type = selectedType!.type;
                          chatProvider.createNewProvider(
                            AIProviderConfig(
                              id: Uuid().v4(),
                              name: nameControllerr.text.trim(),
                              type: type,
                              baseUrl: type.defaultBaseUrl,
                              urlPath: type.defaultPath,
                            )
                          );
                          Navigator.of(context).pop();
                        }
                      : null, // null 会自动禁用按钮
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

}