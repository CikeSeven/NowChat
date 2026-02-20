/// 插件动态 UI 组件类型。
enum PluginUiComponentType {
  button('button'),
  textInput('text_input'),
  toggle('switch'),
  select('select');

  final String wireName;

  const PluginUiComponentType(this.wireName);

  /// 将协议字符串解析为组件类型，未知类型返回 null 由上层做兜底。
  static PluginUiComponentType? fromWireName(String raw) {
    final normalized = raw.trim().toLowerCase();
    for (final value in PluginUiComponentType.values) {
      if (value.wireName == normalized) return value;
    }
    return null;
  }
}

/// 下拉选项定义。
class PluginUiSelectOption {
  /// 展示文本。
  final String label;

  /// 提交值。
  final String value;

  const PluginUiSelectOption({required this.label, required this.value});

  /// 从 JSON 解析下拉选项定义。
  factory PluginUiSelectOption.fromJson(Map<String, dynamic> json) {
    final label = (json['label'] ?? '').toString().trim();
    final value = (json['value'] ?? '').toString();
    if (label.isEmpty) {
      throw const FormatException('插件 UI 下拉选项缺少 label');
    }
    return PluginUiSelectOption(label: label, value: value);
  }
}

/// 单个 UI 组件定义。
class PluginUiComponent {
  /// 组件唯一 ID（事件上报与状态读写依赖该值）。
  final String id;

  /// 组件类型。
  final PluginUiComponentType type;

  /// 组件标题文本。
  final String label;

  /// 组件辅助描述。
  final String description;

  /// 是否启用交互。
  final bool enabled;

  /// 是否可见。
  final bool visible;

  /// 样式关键字（由宿主 UI 解释）。
  final String? style;

  /// 占位提示文本。
  final String? placeholder;

  /// 文本输入是否多行。
  final bool multiline;

  /// 文本值（text_input）。
  final String textValue;

  /// 布尔值（switch）。
  final bool boolValue;

  /// 选中值（select）。
  final String selectedValue;

  /// 下拉候选项（select）。
  final List<PluginUiSelectOption> options;

  const PluginUiComponent({
    required this.id,
    required this.type,
    required this.label,
    required this.description,
    required this.enabled,
    required this.visible,
    required this.style,
    required this.placeholder,
    required this.multiline,
    required this.textValue,
    required this.boolValue,
    required this.selectedValue,
    required this.options,
  });

  /// 从 JSON 解析单个组件定义。
  factory PluginUiComponent.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString().trim();
    final typeName = (json['type'] ?? '').toString().trim();
    final type = PluginUiComponentType.fromWireName(typeName);
    if (id.isEmpty || type == null) {
      throw const FormatException('插件 UI 组件字段不完整(id/type)');
    }

    final rawOptions = json['options'];
    final options =
        rawOptions is List
            ? rawOptions
                .whereType<Map>()
                .map(
                  (item) => PluginUiSelectOption.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
            : const <PluginUiSelectOption>[];

    return PluginUiComponent(
      id: id,
      type: type,
      label: (json['label'] ?? '').toString().trim(),
      description: (json['description'] ?? '').toString().trim(),
      enabled: json['enabled'] != false,
      visible: json['visible'] != false,
      style:
          (json['style'] ?? '').toString().trim().isEmpty
              ? null
              : (json['style'] ?? '').toString().trim(),
      placeholder:
          (json['placeholder'] ?? '').toString().trim().isEmpty
              ? null
              : (json['placeholder'] ?? '').toString().trim(),
      multiline: json['multiline'] == true,
      textValue: (json['value'] ?? '').toString(),
      boolValue: json['value'] == true,
      selectedValue: (json['value'] ?? '').toString(),
      options: options,
    );
  }
}

/// 插件页面状态（由 Python DSL 生成并回传）。
class PluginUiPageState {
  /// 页面标题。
  final String title;

  /// 页面副标题。
  final String subtitle;

  /// 组件列表（按顺序渲染）。
  final List<PluginUiComponent> components;

  /// 页面状态快照（用于事件回传与重建）。
  final Map<String, dynamic> state;

  /// 可选提示消息（通常用于“保存成功”等反馈）。
  final String? message;

  const PluginUiPageState({
    required this.title,
    required this.subtitle,
    required this.components,
    required this.state,
    this.message,
  });

  /// 从 Python DSL 返回值解析页面状态。
  factory PluginUiPageState.fromJson(Map<String, dynamic> json) {
    final rawComponents = json['components'];
    final components =
        rawComponents is List
            ? rawComponents
                .whereType<Map>()
                .map(
                  (item) => PluginUiComponent.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
            : const <PluginUiComponent>[];

    final rawState = json['state'];
    final state =
        rawState is Map
            ? rawState.map((key, value) => MapEntry(key.toString(), value))
            : <String, dynamic>{};

    final messageRaw = (json['message'] ?? '').toString().trim();
    return PluginUiPageState(
      title: (json['title'] ?? '').toString().trim(),
      subtitle: (json['subtitle'] ?? '').toString().trim(),
      components: components,
      state: state,
      message: messageRaw.isEmpty ? null : messageRaw,
    );
  }
}
