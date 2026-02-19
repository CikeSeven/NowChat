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
  final String label;
  final String value;

  const PluginUiSelectOption({
    required this.label,
    required this.value,
  });

  factory PluginUiSelectOption.fromJson(Map<String, dynamic> json) {
    final label = (json['label'] ?? '').toString().trim();
    final value = (json['value'] ?? '').toString();
    if (label.isEmpty) {
      throw const FormatException('插件 UI 下拉选项缺少 label');
    }
    return PluginUiSelectOption(
      label: label,
      value: value,
    );
  }
}

/// 单个 UI 组件定义。
class PluginUiComponent {
  final String id;
  final PluginUiComponentType type;
  final String label;
  final String description;
  final bool enabled;
  final bool visible;
  final String? style;
  final String? placeholder;
  final bool multiline;
  final String textValue;
  final bool boolValue;
  final String selectedValue;
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

  factory PluginUiComponent.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString().trim();
    final typeName = (json['type'] ?? '').toString().trim();
    final type = PluginUiComponentType.fromWireName(typeName);
    if (id.isEmpty || type == null) {
      throw const FormatException('插件 UI 组件字段不完整(id/type)');
    }

    final rawOptions = json['options'];
    final options = rawOptions is List
        ? rawOptions
            .whereType<Map>()
            .map((item) => PluginUiSelectOption.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList()
        : const <PluginUiSelectOption>[];

    return PluginUiComponent(
      id: id,
      type: type,
      label: (json['label'] ?? '').toString().trim(),
      description: (json['description'] ?? '').toString().trim(),
      enabled: json['enabled'] != false,
      visible: json['visible'] != false,
      style: (json['style'] ?? '').toString().trim().isEmpty
          ? null
          : (json['style'] ?? '').toString().trim(),
      placeholder: (json['placeholder'] ?? '').toString().trim().isEmpty
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
  final String title;
  final String subtitle;
  final List<PluginUiComponent> components;
  final Map<String, dynamic> state;
  final String? message;

  const PluginUiPageState({
    required this.title,
    required this.subtitle,
    required this.components,
    required this.state,
    this.message,
  });

  factory PluginUiPageState.fromJson(Map<String, dynamic> json) {
    final rawComponents = json['components'];
    final components = rawComponents is List
        ? rawComponents
            .whereType<Map>()
            .map((item) => PluginUiComponent.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList()
        : const <PluginUiComponent>[];

    final rawState = json['state'];
    final state = rawState is Map
        ? rawState.map(
            (key, value) => MapEntry(key.toString(), value),
          )
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
