import 'package:flutter/material.dart';
import 'package:now_chat/core/models/ai_provider_config.dart';

/// CustomModelDialogResult 类型定义。
class CustomModelDialogResult {
  final String model;
  final String remark;
  final bool supportsVision;
  final bool supportsTools;

  const CustomModelDialogResult({
    required this.model,
    required this.remark,
    required this.supportsVision,
    required this.supportsTools,
  });
}

/// 执行 showCustomModelDialog 逻辑。
Future<CustomModelDialogResult?> showCustomModelDialog({
  required BuildContext context,
  required Set<String> existingModels,
  String? initialModel,
  String? initialRemark,
  ModelFeatureOptions? initialFeatures,
  bool lockModelName = false,
}) async {
  final modelController = TextEditingController(text: initialModel ?? '');
  final remarkController = TextEditingController(text: initialRemark ?? '');
  bool supportsVision = initialFeatures?.supportsVision ?? false;
  bool supportsTools = initialFeatures?.supportsTools ?? false;
  String? errorText;

  // 统一在弹窗内完成校验，返回结果只包含有效输入。
  final result = await showDialog<CustomModelDialogResult>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(lockModelName ? '编辑模型信息' : '手动添加模型'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: modelController,
                  readOnly: lockModelName,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '模型名',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: remarkController,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '备注名（可选）',
                    hintText: '例如：主力模型',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        title: const Text('支持视觉', style: TextStyle(fontSize: 13)),
                        value: supportsVision,
                        onChanged: (value) {
                          setDialogState(() {
                            supportsVision = value ?? false;
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),
                    Expanded(
                      child: CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        title: const Text('支持工具', style: TextStyle(fontSize: 13)),
                        value: supportsTools,
                        onChanged: (value) {
                          setDialogState(() {
                            supportsTools = value ?? false;
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),
                  ],
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      errorText!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final model = modelController.text.trim();
                  final remark = remarkController.text.trim();
                  if (model.isEmpty) {
                    setDialogState(() {
                      errorText = '模型名不能为空';
                    });
                    return;
                  }

                  // 编辑模式下允许“保留原模型名”而不触发重复校验。
                  final isEditingCurrent = lockModelName && initialModel == model;
                  if (existingModels.contains(model) && !isEditingCurrent) {
                    setDialogState(() {
                      errorText = '模型已存在';
                    });
                    return;
                  }

                  Navigator.of(dialogContext).pop(
                    CustomModelDialogResult(
                      model: model,
                      remark: remark,
                      supportsVision: supportsVision,
                      supportsTools: supportsTools,
                    ),
                  );
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      );
    },
  );

  modelController.dispose();
  remarkController.dispose();
  return result;
}
