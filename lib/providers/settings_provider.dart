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
    notifyListeners();
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
