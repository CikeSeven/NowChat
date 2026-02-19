import 'dart:convert';

import 'package:now_chat/core/models/ai_provider_config.dart';
import 'package:now_chat/core/models/agent_profile.dart';
import 'package:now_chat/util/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Storage 类型定义。
class Storage {
  static const _kAPIProvider = 'api_provider';
  static const _kAgentProfiles = 'agent_profiles';
  static const _kAgentExampleSeeded = 'agent_example_seeded';

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

  /// 读取智能体配置列表。
  static Future<List<AgentProfile>> loadAgentProfiles() async {
    AppLogger.i("读取智能体配置");
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAgentProfiles);
    if (raw == null || raw.isEmpty) {
      AppLogger.i("未读取到智能体配置，返回空列表");
      return <AgentProfile>[];
    }
    try {
      final decoded = json.decode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map(
            (item) => AgentProfile.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } catch (e) {
      AppLogger.e("读取智能体配置失败", e);
      return <AgentProfile>[];
    }
  }

  /// 保存智能体配置列表。
  static Future<void> saveAgentProfiles(List<AgentProfile> profiles) async {
    AppLogger.i("保存智能体配置");
    final prefs = await SharedPreferences.getInstance();
    final payload = profiles.map((item) => item.toJson()).toList();
    await prefs.setString(_kAgentProfiles, json.encode(payload));
  }

  /// 是否已写入过首次示例智能体。
  static Future<bool> isAgentExampleSeeded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAgentExampleSeeded) ?? false;
  }

  /// 标记首次示例智能体已写入。
  static Future<void> markAgentExampleSeeded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAgentExampleSeeded, true);
  }
}
