import 'dart:convert';

import 'package:now_chat/core/models/ai_provider_config.dart';
import 'package:now_chat/util/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Storage {
  static const _kAPIProvider = 'api_provider';

  // 读取api列表
  static Future<List<AIProviderConfig>> loadProviders() async {
    AppLogger.i("读取api列表");
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAPIProvider);
    if (raw == null || raw.isEmpty){
      AppLogger.i("未读取到API列表，返回空列表");
      return [];
    }
    try {
      final decoded = json.decode(raw) as List<dynamic>;
      return decoded
        .map((p) => AIProviderConfig.fromJson(p as Map<String, dynamic>))
        .toList();
    } catch (e) {
      AppLogger.e("读取API列表失败", e);
      return [];
    }
  }

  // 保存API列表
  static Future<void> saveProviders(List<AIProviderConfig> providers) async {
    AppLogger.i("保存API列表");
    final prefs = await SharedPreferences.getInstance();
    final jsonList = providers.map((p) => p.toJson()).toList();
    await prefs.setString(_kAPIProvider, json.encode(jsonList));
  }

}
