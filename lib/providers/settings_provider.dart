import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局设置状态：主题、默认会话参数与工具调用默认配置。
class SettingsProvider extends ChangeNotifier with WidgetsBindingObserver {
  /// 新建会话默认参数：与会话设置页初始值保持一致。
  static const double defaultTemperatureValue = 0.7;
  static const double defaultTopPValue = 1.0;
  static const int defaultMaxTokensValue = 8192;
  static const int defaultMaxConversationTurnsValue = 50;
  static const bool defaultStreamingValue = true;
  static const bool defaultToolCallingEnabledValue = true;
  static const int defaultMaxToolCallsValue = 10;
  static const bool defaultExposeImageToolsToChatValue = false;
  static const String defaultImageGenerateSizeValue = '1024x1024';
  static const int defaultImageGenerateCountValue = 1;
  static const int defaultImageQueueConcurrencyValue = 2;

  static const _themeKey = 'theme_mode';
  static const _defaultProviderIdKey = 'default_provider_id';
  static const _defaultModelKey = 'default_model';
  static const _defaultTemperatureKey = 'default_temperature';
  static const _defaultTopPKey = 'default_top_p';
  static const _defaultMaxTokensKey = 'default_max_tokens';
  static const _defaultMaxConversationTurnsKey =
      'default_max_conversation_turns';
  static const _defaultStreamingKey = 'default_streaming';
  static const _defaultToolCallingEnabledKey = 'default_tool_calling_enabled';
  static const _defaultMaxToolCallsKey = 'default_max_tool_calls';
  static const _exposeImageToolsToChatKey = 'expose_image_tools_to_chat';
  static const _defaultImageGenerationProviderIdKey =
      'default_image_generation_provider_id';
  static const _defaultImageGenerationModelKey =
      'default_image_generation_model';
  static const _defaultImageEditProviderIdKey = 'default_image_edit_provider_id';
  static const _defaultImageEditModelKey = 'default_image_edit_model';
  static const _defaultImageGenerateSizeKey = 'default_image_generate_size';
  static const _defaultImageEditSizeKey = 'default_image_edit_size';
  static const _defaultImageGenerateCountKey = 'default_image_generate_count';
  static const _imageQueueConcurrencyKey = 'image_queue_concurrency';

  ThemeMode _themeMode = ThemeMode.system;
  String? _defaultProviderId;
  String? _defaultModel;
  double _defaultTemperature = defaultTemperatureValue;
  double _defaultTopP = defaultTopPValue;
  int _defaultMaxTokens = defaultMaxTokensValue;
  int _defaultMaxConversationTurns = defaultMaxConversationTurnsValue;
  bool _defaultStreaming = defaultStreamingValue;
  bool _defaultToolCallingEnabled = defaultToolCallingEnabledValue;
  int _defaultMaxToolCalls = defaultMaxToolCallsValue;
  bool _exposeImageToolsToChat = defaultExposeImageToolsToChatValue;
  String? _defaultImageGenerationProviderId;
  String? _defaultImageGenerationModel;
  String? _defaultImageEditProviderId;
  String? _defaultImageEditModel;
  String _defaultImageGenerateSize = defaultImageGenerateSizeValue;
  String _defaultImageEditSize = defaultImageGenerateSizeValue;
  int _defaultImageGenerateCount = defaultImageGenerateCountValue;
  int _imageQueueConcurrency = defaultImageQueueConcurrencyValue;

  ThemeMode get themeMode => _themeMode;
  String? get defaultProviderId => _defaultProviderId;
  String? get defaultModel => _defaultModel;
  double get defaultTemperature => _defaultTemperature;
  double get defaultTopP => _defaultTopP;
  int get defaultMaxTokens => _defaultMaxTokens;
  int get defaultMaxConversationTurns => _defaultMaxConversationTurns;
  bool get defaultStreaming => _defaultStreaming;
  bool get defaultToolCallingEnabled => _defaultToolCallingEnabled;
  int get defaultMaxToolCalls => _defaultMaxToolCalls;
  bool get exposeImageToolsToChat => _exposeImageToolsToChat;
  String? get defaultImageGenerationProviderId =>
      _defaultImageGenerationProviderId;
  String? get defaultImageGenerationModel => _defaultImageGenerationModel;
  String? get defaultImageEditProviderId => _defaultImageEditProviderId;
  String? get defaultImageEditModel => _defaultImageEditModel;
  String get defaultImageGenerateSize => _defaultImageGenerateSize;
  /// 兼容旧调用：图片编辑尺寸与生图尺寸统一。
  String get defaultImageEditSize => _defaultImageEditSize;
  int get defaultImageGenerateCount => _defaultImageGenerateCount;
  int get imageQueueConcurrency => _imageQueueConcurrency;

  ThemeMode get effectiveThemeMode {
    // 跟随系统模式下实时读取平台亮度，避免缓存导致主题不同步。
    if (_themeMode != ThemeMode.system) return _themeMode;
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
  }

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  SettingsProvider() {
    WidgetsBinding.instance.addObserver(this);
    // 异步加载设置；加载完成后会自行 notify 刷新 UI。
    _loadSettings();
  }

  /// 从本地持久化存储恢复设置。
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_themeKey);
    if (index != null && index >= 0 && index < ThemeMode.values.length) {
      _themeMode = ThemeMode.values[index];
    }
    final providerId = prefs.getString(_defaultProviderIdKey)?.trim();
    final model = prefs.getString(_defaultModelKey)?.trim();
    _defaultProviderId =
        (providerId == null || providerId.isEmpty) ? null : providerId;
    _defaultModel = (model == null || model.isEmpty) ? null : model;
    _defaultTemperature =
        prefs.getDouble(_defaultTemperatureKey) ?? defaultTemperatureValue;
    _defaultTopP = prefs.getDouble(_defaultTopPKey) ?? defaultTopPValue;
    _defaultMaxTokens = prefs.getInt(_defaultMaxTokensKey) ?? defaultMaxTokensValue;
    _defaultMaxConversationTurns =
        prefs.getInt(_defaultMaxConversationTurnsKey) ??
        defaultMaxConversationTurnsValue;
    _defaultStreaming =
        prefs.getBool(_defaultStreamingKey) ?? defaultStreamingValue;
    _defaultToolCallingEnabled =
        prefs.getBool(_defaultToolCallingEnabledKey) ??
        defaultToolCallingEnabledValue;
    _defaultMaxToolCalls =
        prefs.getInt(_defaultMaxToolCallsKey) ?? defaultMaxToolCallsValue;
    _exposeImageToolsToChat =
        prefs.getBool(_exposeImageToolsToChatKey) ??
        defaultExposeImageToolsToChatValue;
    final imageGenProvider = prefs
        .getString(_defaultImageGenerationProviderIdKey)
        ?.trim();
    final imageGenModel = prefs.getString(_defaultImageGenerationModelKey)?.trim();
    _defaultImageGenerationProviderId =
        (imageGenProvider == null || imageGenProvider.isEmpty)
            ? null
            : imageGenProvider;
    _defaultImageGenerationModel =
        (imageGenModel == null || imageGenModel.isEmpty) ? null : imageGenModel;
    final imageEditProvider = prefs
        .getString(_defaultImageEditProviderIdKey)
        ?.trim();
    final imageEditModel = prefs.getString(_defaultImageEditModelKey)?.trim();
    _defaultImageEditProviderId =
        (imageEditProvider == null || imageEditProvider.isEmpty)
            ? null
            : imageEditProvider;
    _defaultImageEditModel =
        (imageEditModel == null || imageEditModel.isEmpty) ? null : imageEditModel;
    _defaultImageGenerateSize =
        _normalizeImageSize(
          prefs.getString(_defaultImageGenerateSizeKey),
        ) ??
        _normalizeImageSize(
          prefs.getString(_defaultImageEditSizeKey),
        ) ??
        defaultImageGenerateSizeValue;
    // 尺寸配置统一：编辑尺寸与生图尺寸保持一致。
    _defaultImageEditSize = _defaultImageGenerateSize;
    _defaultImageGenerateCount = _normalizeGenerateCount(
      prefs.getInt(_defaultImageGenerateCountKey),
    );
    _imageQueueConcurrency = _normalizeQueueConcurrency(
      prefs.getInt(_imageQueueConcurrencyKey),
    );
    notifyListeners();
  }

  /// 从本地存储强制重载设置。
  ///
  /// 导入应用备份后需要显式调用，确保内存态与磁盘数据一致。
  Future<void> reloadFromStorage() async {
    await _loadSettings();
  }

  /// 更新主题模式并持久化。
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
  }

  /// 设置默认模型（模型与提供方必须成对保存）。
  Future<void> setDefaultModel({
    required String? providerId,
    required String? model,
  }) async {
    final normalizedProvider = providerId?.trim();
    final normalizedModel = model?.trim();
    final nextProvider =
        (normalizedProvider == null || normalizedProvider.isEmpty)
            ? null
            : normalizedProvider;
    final nextModel =
        (normalizedModel == null || normalizedModel.isEmpty)
            ? null
            : normalizedModel;
    _defaultProviderId = nextProvider;
    _defaultModel = nextModel;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    // 任一为空都视为“未设置默认模型”，统一清理两项存储。
    if (nextProvider == null || nextModel == null) {
      await prefs.remove(_defaultProviderIdKey);
      await prefs.remove(_defaultModelKey);
      return;
    }
    await prefs.setString(_defaultProviderIdKey, nextProvider);
    await prefs.setString(_defaultModelKey, nextModel);
  }

  /// 设置默认 temperature。
  Future<void> setDefaultTemperature(double value) async {
    _defaultTemperature = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_defaultTemperatureKey, value);
  }

  /// 设置默认 top_p。
  Future<void> setDefaultTopP(double value) async {
    _defaultTopP = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_defaultTopPKey, value);
  }

  /// 设置默认 max tokens。
  Future<void> setDefaultMaxTokens(int value) async {
    if (value <= 0) return;
    _defaultMaxTokens = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_defaultMaxTokensKey, value);
  }

  /// 设置默认消息轮次上限。
  Future<void> setDefaultMaxConversationTurns(int value) async {
    if (value <= 0) return;
    _defaultMaxConversationTurns = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_defaultMaxConversationTurnsKey, value);
  }

  /// 设置默认是否启用流式输出。
  Future<void> setDefaultStreaming(bool value) async {
    _defaultStreaming = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_defaultStreamingKey, value);
  }

  /// 设置默认是否开启工具调用。
  Future<void> setDefaultToolCallingEnabled(bool value) async {
    _defaultToolCallingEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_defaultToolCallingEnabledKey, value);
  }

  /// 设置默认工具调用次数上限。
  Future<void> setDefaultMaxToolCalls(int value) async {
    if (value <= 0) return;
    _defaultMaxToolCalls = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_defaultMaxToolCallsKey, value);
  }

  /// 设置是否向聊天模型暴露“生图/图片编辑”工具。
  Future<void> setExposeImageToolsToChat(bool value) async {
    _exposeImageToolsToChat = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_exposeImageToolsToChatKey, value);
  }

  /// 设置默认生图模型（文本到图片）。
  Future<void> setDefaultImageGenerationModel({
    required String? providerId,
    required String? model,
  }) async {
    final nextProvider = _normalizeOptional(providerId);
    final nextModel = _normalizeOptional(model);
    _defaultImageGenerationProviderId = nextProvider;
    _defaultImageGenerationModel = nextModel;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await _persistModelPair(
      prefs: prefs,
      providerKey: _defaultImageGenerationProviderIdKey,
      modelKey: _defaultImageGenerationModelKey,
      providerId: nextProvider,
      model: nextModel,
    );
  }

  /// 设置默认图片编辑模型（image-to-image）。
  Future<void> setDefaultImageEditModel({
    required String? providerId,
    required String? model,
  }) async {
    final nextProvider = _normalizeOptional(providerId);
    final nextModel = _normalizeOptional(model);
    _defaultImageEditProviderId = nextProvider;
    _defaultImageEditModel = nextModel;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await _persistModelPair(
      prefs: prefs,
      providerKey: _defaultImageEditProviderIdKey,
      modelKey: _defaultImageEditModelKey,
      providerId: nextProvider,
      model: nextModel,
    );
  }

  /// 设置默认生图尺寸（text-to-image）。
  Future<void> setDefaultImageGenerateSize(String value) async {
    final normalized = _normalizeImageSize(value) ?? defaultImageGenerateSizeValue;
    _defaultImageGenerateSize = normalized;
    _defaultImageEditSize = normalized;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultImageGenerateSizeKey, normalized);
    // 兼容旧版本读取路径，写入同值避免历史分叉。
    await prefs.setString(_defaultImageEditSizeKey, normalized);
  }

  /// 设置默认图片编辑尺寸（image-to-image）。
  Future<void> setDefaultImageEditSize(String value) async {
    // 尺寸配置统一到生图尺寸，编辑入口调用时直接复用同一配置。
    await setDefaultImageGenerateSize(value);
  }

  /// 设置默认每次生图任务生成数量（仅允许 1/2/4）。
  Future<void> setDefaultImageGenerateCount(int value) async {
    final normalized = _normalizeGenerateCount(value);
    _defaultImageGenerateCount = normalized;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_defaultImageGenerateCountKey, normalized);
  }

  /// 设置生图队列并发数。
  Future<void> setImageQueueConcurrency(int value) async {
    final normalized = _normalizeQueueConcurrency(value);
    _imageQueueConcurrency = normalized;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_imageQueueConcurrencyKey, normalized);
  }

  /// 恢复所有默认对话参数并清理本地覆盖项。
  Future<void> restoreDefaultChatParams() async {
    _defaultProviderId = null;
    _defaultModel = null;
    _defaultTemperature = defaultTemperatureValue;
    _defaultTopP = defaultTopPValue;
    _defaultMaxTokens = defaultMaxTokensValue;
    _defaultMaxConversationTurns = defaultMaxConversationTurnsValue;
    _defaultStreaming = defaultStreamingValue;
    _defaultToolCallingEnabled = defaultToolCallingEnabledValue;
    _defaultMaxToolCalls = defaultMaxToolCallsValue;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_defaultProviderIdKey);
    await prefs.remove(_defaultModelKey);
    await prefs.remove(_defaultTemperatureKey);
    await prefs.remove(_defaultTopPKey);
    await prefs.remove(_defaultMaxTokensKey);
    await prefs.remove(_defaultMaxConversationTurnsKey);
    await prefs.remove(_defaultStreamingKey);
    await prefs.remove(_defaultToolCallingEnabledKey);
    await prefs.remove(_defaultMaxToolCallsKey);
  }

  /// 主题快捷切换（浅色/深色）。
  ///
  /// 当当前模式为系统跟随时，切换后会直接进入深色模式。
  void toggleTheme() {
    if (_themeMode == ThemeMode.dark) {
      setThemeMode(ThemeMode.light);
    } else {
      setThemeMode(ThemeMode.dark);
    }
  }

  /// 将可选字符串标准化为 `null | 非空 trim`。
  String? _normalizeOptional(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized;
  }

  /// 规范化图片尺寸：空值回退为 null，非空直接返回 trim 文本。
  String? _normalizeImageSize(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized;
  }

  /// 规范化队列并发数，限制在 1~4。
  int _normalizeQueueConcurrency(int? value) {
    final next = value ?? defaultImageQueueConcurrencyValue;
    if (next < 1) return 1;
    if (next > 4) return 4;
    return next;
  }

  /// 规范化生图数量，仅允许 1/2/4。
  int _normalizeGenerateCount(int? value) {
    switch (value) {
      case 2:
      case 4:
        return value!;
      case 1:
      default:
        return 1;
    }
  }

  /// 持久化“provider + model”成对配置。
  ///
  /// 任一为空时统一清理，避免出现“只有 provider 或只有 model”的半配置。
  Future<void> _persistModelPair({
    required SharedPreferences prefs,
    required String providerKey,
    required String modelKey,
    required String? providerId,
    required String? model,
  }) async {
    if (providerId == null || model == null) {
      await prefs.remove(providerKey);
      await prefs.remove(modelKey);
      return;
    }
    await prefs.setString(providerKey, providerId);
    await prefs.setString(modelKey, model);
  }

  @override
  void didChangePlatformBrightness() {
    // 仅系统跟随模式需要响应平台亮度变化。
    if (_themeMode == ThemeMode.system) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
