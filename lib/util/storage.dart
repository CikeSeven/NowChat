import 'dart:convert';

import 'package:now_chat/core/models/ai_provider_config.dart';
import 'package:now_chat/core/models/agent_profile.dart';
import 'package:now_chat/core/models/image_generation_record.dart';
import 'package:now_chat/core/models/image_generation_task.dart';
import 'package:now_chat/util/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 轻量本地存储门面（SharedPreferences）。
///
/// 设计原则：
/// 1. 仅存储小体量配置与列表快照（API/智能体等）。
/// 2. 读取失败时返回安全兜底值，避免阻断应用启动。
/// 3. 所有序列化入口集中在此，便于后续迁移存储方案。
class Storage {
  /// API 提供方列表 JSON 存储键。
  static const _kAPIProvider = 'api_provider';

  /// 智能体列表 JSON 存储键。
  static const _kAgentProfiles = 'agent_profiles';
  static const _kImageGenerationHistory = 'image_generation_history';
  static const _kImageGenerationQueueTasks = 'image_generation_queue_tasks';

  /// 首次示例智能体是否已注入标记。
  static const _kAgentExampleSeeded = 'agent_example_seeded';

  /// 读取 API 提供方列表。
  ///
  /// 失败策略：解析失败返回空列表并记录日志，不抛异常。
  static Future<List<AIProviderConfig>> loadProviders() async {
    AppLogger.i("读取api列表");
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAPIProvider);
    if (raw == null || raw.isEmpty) {
      AppLogger.i("未读取到API列表，返回空列表");
      return [];
    }
    try {
      final decoded = json.decode(raw) as List<dynamic>;
      return decoded
          .map((p) => AIProviderConfig.fromJson(p as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // 历史数据损坏或版本不兼容时，回退为空列表以保证页面可继续使用。
      AppLogger.e("读取API列表失败", e);
      return [];
    }
  }

  /// 保存 API 提供方列表。
  ///
  /// 使用“整表覆盖写入”策略，保持数据结构简单可读。
  static Future<void> saveProviders(List<AIProviderConfig> providers) async {
    AppLogger.i("保存API列表");
    final prefs = await SharedPreferences.getInstance();
    final jsonList = providers.map((p) => p.toJson()).toList();
    await prefs.setString(_kAPIProvider, json.encode(jsonList));
  }

  /// 读取智能体配置列表。
  ///
  /// 失败策略与 API 列表一致：返回空列表并记录错误。
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
          .map((item) => AgentProfile.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (e) {
      // 容错：智能体配置解析失败不影响主流程。
      AppLogger.e("读取智能体配置失败", e);
      return <AgentProfile>[];
    }
  }

  /// 保存智能体配置列表。
  ///
  /// 与读取配套，统一按 JSON 数组写入。
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
  ///
  /// 该标记用于避免每次启动都重复插入示例数据。
  static Future<void> markAgentExampleSeeded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAgentExampleSeeded, true);
  }

  /// 读取“工作台生图”独立历史列表。
  static Future<List<ImageGenerationRecord>> loadImageGenerationHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kImageGenerationHistory);
    if (raw == null || raw.trim().isEmpty) return <ImageGenerationRecord>[];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return <ImageGenerationRecord>[];
      return decoded
          .whereType<Map>()
          .map(
            (item) => ImageGenerationRecord.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } catch (error) {
      AppLogger.e('读取生图历史失败', error);
      return <ImageGenerationRecord>[];
    }
  }

  /// 保存“工作台生图”独立历史列表。
  ///
  /// 为避免 SharedPreferences 存储无限增长，这里仅保留最近 200 条。
  static Future<void> saveImageGenerationHistory(
    List<ImageGenerationRecord> history,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = List<ImageGenerationRecord>.from(history)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final trimmed = sorted.take(200).toList(growable: false);
    final payload = trimmed.map((item) => item.toJson()).toList();
    await prefs.setString(_kImageGenerationHistory, json.encode(payload));
  }

  /// 读取生图队列任务列表（含排队/进行中/已完成状态）。
  static Future<List<ImageGenerationTask>> loadImageGenerationQueueTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kImageGenerationQueueTasks);
    if (raw == null || raw.trim().isEmpty) return <ImageGenerationTask>[];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return <ImageGenerationTask>[];
      return decoded
          .whereType<Map>()
          .map(
            (item) => ImageGenerationTask.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } catch (error) {
      AppLogger.e('读取生图队列失败', error);
      return <ImageGenerationTask>[];
    }
  }

  /// 保存生图队列任务列表。
  ///
  /// 为避免本地数据持续膨胀，仅保留最近 300 条记录。
  static Future<void> saveImageGenerationQueueTasks(
    List<ImageGenerationTask> tasks,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = List<ImageGenerationTask>.from(tasks)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final trimmed = sorted.take(300).toList(growable: false);
    final payload = trimmed.map((item) => item.toJson()).toList();
    await prefs.setString(_kImageGenerationQueueTasks, json.encode(payload));
  }
}
