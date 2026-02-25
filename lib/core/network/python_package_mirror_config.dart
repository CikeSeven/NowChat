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
/// 1. 优先使用 Chaquopy wheel 源（适配 Android ABI 的包优先级最高）。
/// 2. 解析入口使用 simple index：`/simple/<name>/`。
class PythonPackageMirrorConfig {
  static const String directId = 'direct';
  static const String customId = 'custom';
  static const String pypiTsinghuaSimpleBaseUrl =
      'https://pypi.tuna.tsinghua.edu.cn/simple';
  static const String pypiOfficialSimpleBaseUrl = 'https://pypi.org/simple';

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

  /// PyPI simple 回退链路（按顺序尝试）。
  ///
  /// 说明：
  /// - `requirements` 解析不到 Chaquopy 候选时，才会回退到该链路。
  /// - 运行时侧会进一步限制 wheel 类型（仅允许纯 Python wheel）。
  static const List<String> pypiFallbackSimpleBaseUrls = <String>[
    pypiTsinghuaSimpleBaseUrl,
    pypiOfficialSimpleBaseUrl,
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

  /// 构造指定包的 simple index 候选地址。
  ///
  /// 兼容：
  /// 1. `<base>/<package>/`（Chaquopy 常见形式）
  /// 2. `<base>/simple/<package>/`（标准 PyPI simple 形式）
  static List<String> buildSimpleIndexUrls({
    required String packageName,
    required String mirrorId,
    String customMirrorBaseUrl = '',
  }) {
    final baseUrl = resolveBaseUrl(
      mirrorId: mirrorId,
      customMirrorBaseUrl: customMirrorBaseUrl,
    );
    final normalizedPackage = packageName.trim().toLowerCase();
    final effectiveBase =
        baseUrl.trim().isEmpty ? 'https://chaquo.com/pypi-13.1' : baseUrl;
    return <String>[
      '$effectiveBase/$normalizedPackage/',
      '$effectiveBase/simple/$normalizedPackage/',
    ];
  }

  /// 构造 PyPI simple 候选地址（仅 simple 风格）。
  ///
  /// 注意：
  /// - 这里不拼接 `/<package>/` 旧格式，避免对 PyPI 官方源产生无效请求。
  static List<String> buildPypiSimpleIndexUrls({
    required String packageName,
    required String simpleBaseUrl,
  }) {
    final normalizedPackage = packageName.trim().toLowerCase();
    final normalizedBase = normalizeCustomBaseUrl(simpleBaseUrl);
    if (normalizedPackage.isEmpty || normalizedBase.isEmpty) {
      return const <String>[];
    }
    return <String>['$normalizedBase/$normalizedPackage/'];
  }
}
