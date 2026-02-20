/// GitHub 镜像预设模型。
class GithubMirrorPreset {
  /// 镜像 ID（用于持久化与逻辑判断）。
  final String id;

  /// 镜像展示名。
  final String name;

  /// 镜像说明文案。
  final String description;

  /// 镜像基础地址（空字符串代表直连）。
  final String baseUrl;

  const GithubMirrorPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.baseUrl,
  });
}

/// GitHub 镜像配置中心。
///
/// 插件中心与应用更新检查都应从该处读取镜像清单，避免分散维护。
class GithubMirrorConfig {
  static const String directId = 'direct';
  static const String ghfastId = 'ghfast';
  static const String ghllkkId = 'ghllkk';
  static const String ghproxyNetId = 'ghproxy_net';
  static const String customId = 'custom';

  /// 镜像预设清单（统一供插件中心与更新检查使用）。
  static const List<GithubMirrorPreset> presets = <GithubMirrorPreset>[
    GithubMirrorPreset(
      id: directId,
      name: '不走镜像',
      description: '直接访问 GitHub',
      baseUrl: '',
    ),
    GithubMirrorPreset(
      id: ghfastId,
      name: 'ghfast.top',
      description: '前缀代理：ghfast.top/https://github.com/...',
      baseUrl: 'https://ghfast.top',
    ),
    GithubMirrorPreset(
      id: ghllkkId,
      name: 'gh.llkk.cc',
      description: '前缀代理：gh.llkk.cc/https://github.com/...',
      baseUrl: 'https://gh.llkk.cc',
    ),
    GithubMirrorPreset(
      id: ghproxyNetId,
      name: 'ghproxy.net',
      description: '前缀代理：ghproxy.net/https://github.com/...',
      baseUrl: 'https://ghproxy.net',
    ),
    GithubMirrorPreset(
      id: customId,
      name: '自定义代理',
      description: '前缀代理：<你的地址>/https://github.com/...',
      baseUrl: '',
    ),
  ];

  /// 自动回退链路（用于更新检查）：不包含自定义项。
  static const List<String> automaticFallbackMirrorIds = <String>[
    directId,
    ghfastId,
    ghllkkId,
    ghproxyNetId,
  ];

  /// 根据镜像 ID 查找预设。
  static GithubMirrorPreset? findById(String id) {
    for (final preset in presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  /// 规范化用户输入的自定义代理地址。
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

  /// 对 URL 应用镜像。
  ///
  /// [onlyGithubHosts] 为 true 时，仅对 GitHub 相关域名生效。
  static String applyMirrorToUrl({
    required String url,
    required String mirrorId,
    String customMirrorBaseUrl = '',
    bool onlyGithubHosts = true,
  }) {
    final normalizedId = mirrorId.trim().isEmpty ? directId : mirrorId.trim();
    if (normalizedId == directId) return url;

    if (onlyGithubHosts && !_isGithubRelatedUrl(url)) {
      return url;
    }

    final baseUrl =
        normalizedId == customId
            ? normalizeCustomBaseUrl(customMirrorBaseUrl)
            : (findById(normalizedId)?.baseUrl ?? '');
    if (baseUrl.trim().isEmpty) return url;
    return '$baseUrl/$url';
  }

  /// 判断是否为 GitHub 相关域名链接。
  static bool _isGithubRelatedUrl(String rawUrl) {
    Uri uri;
    try {
      uri = Uri.parse(rawUrl);
    } catch (_) {
      return false;
    }
    final host = uri.host.toLowerCase();
    return host == 'github.com' ||
        host == 'raw.githubusercontent.com' ||
        host == 'codeload.github.com' ||
        host == 'api.github.com';
  }
}
