import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const double defaultTemperatureValue = 0.7;
  static const double defaultTopPValue = 1.0;
  static const int defaultMaxTokensValue = 8192;
  static const int defaultMaxConversationTurnsValue = 50;
  static const bool defaultStreamingValue = true;
  static const bool defaultToolCallingEnabledValue = true;
  static const int defaultMaxToolCallsValue = 5;

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
    if (_themeMode != ThemeMode.system) return _themeMode;
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
  }

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  SettingsProvider() {
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

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

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
  }

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
    if (nextProvider == null || nextModel == null) {
      await prefs.remove(_defaultProviderIdKey);
      await prefs.remove(_defaultModelKey);
      return;
    }
    await prefs.setString(_defaultProviderIdKey, nextProvider);
    await prefs.setString(_defaultModelKey, nextModel);
  }

  Future<void> setDefaultTemperature(double value) async {
    _defaultTemperature = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_defaultTemperatureKey, value);
  }

  Future<void> setDefaultTopP(double value) async {
    _defaultTopP = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_defaultTopPKey, value);
  }

  Future<void> setDefaultMaxTokens(int value) async {
    if (value <= 0) return;
    _defaultMaxTokens = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_defaultMaxTokensKey, value);
  }

  Future<void> setDefaultMaxConversationTurns(int value) async {
    if (value <= 0) return;
    _defaultMaxConversationTurns = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_defaultMaxConversationTurnsKey, value);
  }

  Future<void> setDefaultStreaming(bool value) async {
    _defaultStreaming = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_defaultStreamingKey, value);
  }

  Future<void> setDefaultToolCallingEnabled(bool value) async {
    _defaultToolCallingEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_defaultToolCallingEnabledKey, value);
  }

  Future<void> setDefaultMaxToolCalls(int value) async {
    if (value <= 0) return;
    _defaultMaxToolCalls = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_defaultMaxToolCallsKey, value);
  }

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

  void toggleTheme() {
    if (_themeMode == ThemeMode.dark) {
      setThemeMode(ThemeMode.light);
    } else {
      setThemeMode(ThemeMode.dark);
    }
  }

  @override
  void didChangePlatformBrightness() {
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
