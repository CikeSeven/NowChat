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
/// 该配置用于 requirements 运行时安装：
/// 1. 解析包元数据（`/pypi/<name>/json`）。
/// 2. 重写 `files.pythonhosted.org` 下载地址到镜像域名。
class PythonPackageMirrorConfig {
  static const String directId = 'direct';
  static const String tsinghuaId = 'tsinghua';
  static const String aliyunId = 'aliyun';
  static const String ustcId = 'ustc';
  static const String customId = 'custom';

  /// 镜像预设清单。
  static const List<PythonPackageMirrorPreset> presets =
      <PythonPackageMirrorPreset>[
        PythonPackageMirrorPreset(
          id: directId,
          name: 'PyPI 官方',
          description: 'https://pypi.org',
          baseUrl: 'https://pypi.org',
        ),
        PythonPackageMirrorPreset(
          id: tsinghuaId,
          name: '清华镜像',
          description: 'https://pypi.tuna.tsinghua.edu.cn',
          baseUrl: 'https://pypi.tuna.tsinghua.edu.cn',
        ),
        PythonPackageMirrorPreset(
          id: aliyunId,
          name: '阿里云镜像',
          description: 'https://mirrors.aliyun.com/pypi',
          baseUrl: 'https://mirrors.aliyun.com/pypi',
        ),
        PythonPackageMirrorPreset(
          id: ustcId,
          name: '中科大镜像',
          description: 'https://mirrors.ustc.edu.cn/pypi/web',
          baseUrl: 'https://mirrors.ustc.edu.cn/pypi/web',
        ),
        PythonPackageMirrorPreset(
          id: customId,
          name: '自定义镜像',
          description: 'https://<你的镜像根路径>',
          baseUrl: '',
        ),
      ];

  /// 自动回退顺序：
  /// 先官方，失败后尝试国内镜像，兼顾全球与国内网络环境。
  static const List<String> automaticFallbackMirrorIds = <String>[
    directId,
    tsinghuaId,
    aliyunId,
    ustcId,
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

  /// 构造指定包的元数据 JSON 地址。
  static String buildPackageJsonUrl({
    required String packageName,
    required String mirrorId,
    String customMirrorBaseUrl = '',
  }) {
    final baseUrl = resolveBaseUrl(
      mirrorId: mirrorId,
      customMirrorBaseUrl: customMirrorBaseUrl,
    );
    if (baseUrl.trim().isEmpty) {
      return 'https://pypi.org/pypi/$packageName/json';
    }
    return '$baseUrl/pypi/$packageName/json';
  }

  /// 将 PyPI 文件下载链接重写到镜像。
  ///
  /// 部分镜像返回的 `url` 仍指向 `files.pythonhosted.org`，这里主动重写到镜像域名，
  /// 避免在国内网络环境下解析成功但下载超时。
  static String rewritePackageDownloadUrl({
    required String rawUrl,
    required String mirrorId,
    String customMirrorBaseUrl = '',
  }) {
    final baseUrl = resolveBaseUrl(
      mirrorId: mirrorId,
      customMirrorBaseUrl: customMirrorBaseUrl,
    );
    if (baseUrl.trim().isEmpty) return rawUrl;

    Uri uri;
    try {
      uri = Uri.parse(rawUrl);
    } catch (_) {
      return rawUrl;
    }

    final host = uri.host.toLowerCase();
    final isOfficialPyPiHost =
        host == 'files.pythonhosted.org' ||
        host == 'pypi.org' ||
        host == 'pythonhosted.org';
    if (!isOfficialPyPiHost) return rawUrl;
    return '$baseUrl${uri.path}';
  }
}
