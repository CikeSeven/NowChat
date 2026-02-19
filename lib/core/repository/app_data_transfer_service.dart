import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:isar/isar.dart';
import 'package:now_chat/core/models/agent_profile.dart';
import 'package:now_chat/core/models/ai_provider_config.dart';
import 'package:now_chat/core/models/chat_session.dart';
import 'package:now_chat/core/models/message.dart';
import 'package:now_chat/util/storage.dart';

/// 应用数据导入导出服务（不包含插件数据）。
class AppDataTransferService {
  static const int backupFormatVersion = 1;

  final Isar isar;

  const AppDataTransferService({required this.isar});

  /// 构建完整备份 JSON。
  ///
  /// [includeApiKeys] 为 `true` 时会将 API key 一并导出。
  Future<Map<String, dynamic>> buildBackupJson({
    required bool includeApiKeys,
  }) async {
    final providers = await Storage.loadProviders();
    final agents = await Storage.loadAgentProfiles();
    final chats = await isar.chatSessions.where().sortByLastUpdatedDesc().findAll();
    final messages = await isar.messages.where().sortByTimestamp().findAll();

    final providerPayload =
        providers.map((item) {
          if (includeApiKeys) return item.toJson();
          return item.copyWith(apiKey: null).toJson();
        }).toList();

    return <String, dynamic>{
      'formatVersion': backupFormatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'app': 'NowChat',
      'includeApiKeys': includeApiKeys,
      'data': <String, dynamic>{
        'providers': providerPayload,
        'agents': agents.map((item) => item.toJson()).toList(),
        'chatSessions': chats.map((item) => item.toJson()).toList(),
        'messages': messages.map((item) => item.toJson()).toList(),
      },
    };
  }

  /// 打开系统保存文件对话框并导出备份。
  ///
  /// 返回值为最终保存路径（用户取消时返回 `null`）。
  Future<String?> exportBackupToUserSelectedFile({
    required bool includeApiKeys,
  }) async {
    final payload = await buildBackupJson(includeApiKeys: includeApiKeys);
    final prettyJson = const JsonEncoder.withIndent('  ').convert(payload);
    final bytes = Uint8List.fromList(utf8.encode(prettyJson));
    final now = DateTime.now();
    final fileName =
        'nowchat-backup-${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.json';

    final path = await FilePicker.platform.saveFile(
      dialogTitle: '保存备份文件',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
      bytes: bytes,
    );
    if (path == null || path.trim().isEmpty) return null;

    // 某些平台 saveFile 可能只返回路径但不落盘，这里尝试兜底写入。
    // 注意：在 Android 的部分文档提供者路径下，二次写入可能无权限，
    // 但 saveFile 本身已成功保存，此时不能再抛错影响用户提示。
    if (!path.startsWith('content://')) {
      try {
        final file = File(path);
        if (!file.existsSync()) {
          await file.writeAsBytes(bytes, flush: true);
        }
      } catch (_) {
        // 忽略兜底写入失败，避免出现“文件已保存但提示失败”的误报。
      }
    }
    return path;
  }

  /// 从系统文件选择器导入备份并执行“清空后导入”。
  ///
  /// 返回值为选中的文件名（用户取消时返回 `null`）。
  Future<String?> importFromUserSelectedFileAndReplaceAll() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final picked = result.files.first;
    String rawJson = '';
    final path = picked.path;
    if (path != null && path.trim().isNotEmpty) {
      rawJson = await File(path).readAsString();
    } else if (picked.bytes != null) {
      rawJson = utf8.decode(picked.bytes!);
    } else {
      throw const FormatException('无法读取备份文件内容');
    }

    await importFromRawJsonAndReplaceAll(rawJson);
    return picked.name;
  }

  /// 从 JSON 字符串导入并执行“清空后导入”。
  Future<void> importFromRawJsonAndReplaceAll(String rawJson) async {
    final payload = _parseBackupPayload(rawJson);
    final data = payload['data'] as Map<String, dynamic>;

    final providers = _parseProviders(data['providers']);
    final agents = _parseAgents(data['agents']);
    final importedChats = _parseChats(data['chatSessions']);
    final messages = _parseMessages(data['messages']);

    // 先写非 Isar 数据，保证导入完成后 Provider 重载即可读到新配置。
    await Storage.saveProviders(providers);
    await Storage.saveAgentProfiles(agents);
    await Storage.markAgentExampleSeeded();

    // 再在单事务内替换会话与消息。
    await isar.writeTxn(() async {
      await isar.messages.where().deleteAll();
      await isar.chatSessions.where().deleteAll();

      final chatIdMap = <int, int>{};
      for (final imported in importedChats) {
        // 导入后统一纠正为非生成中状态，避免出现历史会话卡在生成态。
        imported.session.isGenerating = false;
        final newId = await isar.chatSessions.put(imported.session);
        if (imported.sourceId != null) {
          chatIdMap[imported.sourceId!] = newId;
        }
      }

      for (final message in messages) {
        final mappedChatId = chatIdMap[message.chatId];
        if (mappedChatId == null) {
          // 备份中引用了不存在的会话，直接忽略该消息，避免脏数据写入。
          continue;
        }
        message.chatId = mappedChatId;
        await isar.messages.put(message);
      }
    });
  }

  Map<String, dynamic> _parseBackupPayload(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('备份文件格式错误：根节点必须是对象');
    }
    final versionRaw = decoded['formatVersion'];
    final version = versionRaw is num ? versionRaw.toInt() : -1;
    if (version != backupFormatVersion) {
      throw FormatException(
        '备份版本不支持：$version（当前仅支持 v$backupFormatVersion）',
      );
    }
    final dataRaw = decoded['data'];
    if (dataRaw is! Map<String, dynamic>) {
      throw const FormatException('备份文件格式错误：缺少 data 对象');
    }
    return decoded;
  }

  List<AIProviderConfig> _parseProviders(dynamic raw) {
    if (raw == null) return <AIProviderConfig>[];
    if (raw is! List) {
      throw const FormatException('备份文件格式错误：providers 必须是数组');
    }
    return raw
        .whereType<Map>()
        .map((item) => AIProviderConfig.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  List<AgentProfile> _parseAgents(dynamic raw) {
    if (raw == null) return <AgentProfile>[];
    if (raw is! List) {
      throw const FormatException('备份文件格式错误：agents 必须是数组');
    }
    return raw
        .whereType<Map>()
        .map((item) => AgentProfile.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  List<_ImportedChat> _parseChats(dynamic raw) {
    if (raw == null) return <_ImportedChat>[];
    if (raw is! List) {
      throw const FormatException('备份文件格式错误：chatSessions 必须是数组');
    }
    return raw.whereType<Map>().map((item) {
      final json = Map<String, dynamic>.from(item);
      final sourceIdRaw = json['id'];
      final sourceId =
          sourceIdRaw is num ? sourceIdRaw.toInt() : int.tryParse('$sourceIdRaw');
      return _ImportedChat(
        sourceId: sourceId,
        session: ChatSession.fromJson(json),
      );
    }).toList();
  }

  List<Message> _parseMessages(dynamic raw) {
    if (raw == null) return <Message>[];
    if (raw is! List) {
      throw const FormatException('备份文件格式错误：messages 必须是数组');
    }
    return raw
        .whereType<Map>()
        .map((item) => Message.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }
}

/// 导入会话临时模型：保留旧 ID 以便映射消息关联关系。
class _ImportedChat {
  final int? sourceId;
  final ChatSession session;

  const _ImportedChat({required this.sourceId, required this.session});
}
