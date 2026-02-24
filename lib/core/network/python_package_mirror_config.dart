/// Python 包镜像预设模型。
class PythonPackageMirrorPreset {
  /// 镜像 ID（用于持久化与逻辑判断）。
  final String id;

  /// 镜像展示名。
  final String name;

  /// 镜像说明文案。
  final String description;

  /// 镜像基础地址（空字符串代表直连官方源）。
  final String baseUrl;

  const PythonPackageMirrorPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.baseUrl,
  });
}

/// Python 包镜像配置中心。
///
/// 该配置用于 requirements 运行时安装。
///
/// 约束：
/// 1. 安卓端只使用 Chaquopy wheel 源，不走 PyPI JSON。
/// 2. 解析入口使用 simple index：`/simple/<name>/`。
class PythonPackageMirrorConfig {
  static const String directId = 'direct';
  static const String customId = 'custom';

  /// 镜像预设清单。
  static const List<PythonPackageMirrorPreset> presets =
      <PythonPackageMirrorPreset>[
        PythonPackageMirrorPreset(
          id: directId,
          name: 'Chaquopy 官方源',
          description: 'https://chaquo.com/pypi-13.1',
          baseUrl: 'https://chaquo.com/pypi-13.1',
        ),
        PythonPackageMirrorPreset(
          id: customId,
          name: '自定义 Chaquopy 镜像',
          description: 'https://<你的镜像根路径>/pypi-13.1',
          baseUrl: '',
        ),
      ];

  /// 自动回退顺序：默认只回退到官方源。
  ///
  /// 说明：自定义镜像是否启用由业务侧显式传入 mirrorId 控制。
  static const List<String> automaticFallbackMirrorIds = <String>[
    directId,
  ];

  /// 根据镜像 ID 查找预设。
  static PythonPackageMirrorPreset? findById(String id) {
    for (final preset in presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  /// 规范化用户输入的自定义镜像地址。
  ///
  /// 返回空字符串代表输入无效。
  static String normalizeCustomBaseUrl(String input) {
    var value = input.trim();
    if (value.isEmpty) return '';
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'https://$value';
    }
    Uri uri;
    try {
      uri = Uri.parse(value);
    } catch (_) {
      return '';
    }
    if (uri.host.trim().isEmpty) return '';
    var normalized = uri.toString();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  /// 根据镜像 ID 解析基础地址。
  static String resolveBaseUrl({
    required String mirrorId,
    String customMirrorBaseUrl = '',
  }) {
    final normalizedId = mirrorId.trim().isEmpty ? directId : mirrorId.trim();
    if (normalizedId == customId) {
      return normalizeCustomBaseUrl(customMirrorBaseUrl);
    }
    final preset = findById(normalizedId);
    return preset?.baseUrl ?? '';
  }

  /// 构造指定包的 simple index 地址。
  static String buildSimpleIndexUrl({
    required String packageName,
    required String mirrorId,
    String customMirrorBaseUrl = '',
  }) {
    final baseUrl = resolveBaseUrl(
      mirrorId: mirrorId,
      customMirrorBaseUrl: customMirrorBaseUrl,
    );
    if (baseUrl.trim().isEmpty) {
      return 'https://chaquo.com/pypi-13.1/simple/$packageName/';
    }
    return '$baseUrl/simple/$packageName/';
  }
}
