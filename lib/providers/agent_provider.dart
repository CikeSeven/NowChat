import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:now_chat/core/models/agent_profile.dart';
import 'package:now_chat/core/models/ai_provider_config.dart';
import 'package:now_chat/core/models/chat_session.dart';
import 'package:now_chat/core/models/message.dart';
import 'package:now_chat/core/network/api_service.dart';
import 'package:now_chat/util/storage.dart';

/// 一次性对话的结果快照。
class AgentOneShotResult {
  final String input;
  final String content;
  final String reasoning;
  final bool interrupted;
  final String? error;
  final DateTime timestamp;

  const AgentOneShotResult({
    required this.input,
    required this.content,
    required this.reasoning,
    required this.interrupted,
    required this.error,
    required this.timestamp,
  });
}

/// 一次性请求运行参数。
class AgentOneShotRequest {
  final AgentProfile agent;
  final AIProviderConfig provider;
  final String model;
  final String input;
  final double temperature;
  final double topP;
  final int maxTokens;
  final bool isStreaming;

  const AgentOneShotRequest({
    required this.agent,
    required this.provider,
    required this.model,
    required this.input,
    required this.temperature,
    required this.topP,
    required this.maxTokens,
    required this.isStreaming,
  });
}

/// 智能体数据与一次性对话状态管理。
class AgentProvider with ChangeNotifier {
  final Isar isar;

  final List<AgentProfile> _agents = <AgentProfile>[];
  bool _initialized = false;
  bool _isGenerating = false;
  String _streamingContent = '';
  String _streamingReasoning = '';
  AgentOneShotResult? _lastResult;
  GenerationAbortController? _abortController;

  List<AgentProfile> get agents => List.unmodifiable(_agents);
  bool get isGenerating => _isGenerating;
  String get streamingContent => _streamingContent;
  String get streamingReasoning => _streamingReasoning;
  AgentOneShotResult? get lastResult => _lastResult;

  AgentProvider(this.isar) {
    loadAgents();
  }

  /// 加载智能体列表。
  Future<void> loadAgents() async {
    if (_initialized) return;
    _initialized = true;
    final loaded = await Storage.loadAgentProfiles();
    await _seedExampleAgentIfNeeded(loaded);
    _agents
      ..clear()
      ..addAll(loaded);
    _sortAgents();
    notifyListeners();
  }

  /// 根据 ID 获取智能体。
  AgentProfile? getById(String id) {
    try {
      return _agents.firstWhere((item) => item.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 新建智能体并持久化。
  Future<void> createAgent(AgentProfile profile) async {
    _agents.add(profile);
    _sortAgents();
    await Storage.saveAgentProfiles(_agents);
    notifyListeners();
  }

  /// 更新智能体并持久化。
  Future<void> updateAgent(AgentProfile profile) async {
    final index = _agents.indexWhere((item) => item.id == profile.id);
    if (index == -1) return;
    _agents[index] = profile;
    _sortAgents();
    await Storage.saveAgentProfiles(_agents);
    notifyListeners();
  }

  /// 删除智能体并持久化。
  Future<void> deleteAgent(String id) async {
    _agents.removeWhere((item) => item.id == id);
    await Storage.saveAgentProfiles(_agents);
    notifyListeners();
  }

  /// 中断当前一次性请求。
  void interruptOneShot() {
    _abortController?.abort();
  }

  /// 发起一次性请求（每次仅使用本次输入，不带历史上下文）。
  Future<void> runOneShot(AgentOneShotRequest request) async {
    final normalizedInput = request.input.trim();
    if (normalizedInput.isEmpty || _isGenerating) return;

    final tempSession = ChatSession(
      title: '智能体临时会话',
      providerId: request.provider.id,
      model: request.model,
      systemPrompt: request.agent.prompt.trim(),
      temperature: request.temperature,
      topP: request.topP,
      maxTokens: request.maxTokens,
      maxConversationTurns: 1,
      isStreaming: request.isStreaming,
      isGenerating: true,
      createdAt: DateTime.now(),
      lastUpdated: DateTime.now(),
    );
    final overrideMessages = <Message>[
      Message(
        chatId: -1,
        role: 'user',
        content: normalizedInput,
        timestamp: DateTime.now(),
      ),
    ];

    _abortController = GenerationAbortController();
    _isGenerating = true;
    _streamingContent = '';
    _streamingReasoning = '';
    _lastResult = null;
    notifyListeners();

    var interrupted = false;
    String? error;
    try {
      if (request.isStreaming && request.provider.requestMode.supportsStreaming) {
        await ApiService.sendChatRequestStreaming(
          provider: request.provider,
          session: tempSession,
          isar: isar,
          abortController: _abortController,
          overrideMessages: overrideMessages,
          onStream: (deltaContent, deltaReasoning) {
            if (deltaReasoning != null && deltaReasoning.isNotEmpty) {
              _streamingReasoning += deltaReasoning;
            }
            if (deltaContent.isNotEmpty) {
              _streamingContent += deltaContent;
            }
            notifyListeners();
          },
        );
      } else {
        final response = await ApiService.sendChatRequest(
          provider: request.provider,
          session: tempSession,
          isar: isar,
          abortController: _abortController,
          overrideMessages: overrideMessages,
        );
        _streamingContent = (response['content'] ?? '').toString();
        _streamingReasoning = (response['reasoning'] ?? '').toString();
      }
    } on GenerationAbortedException {
      interrupted = true;
    } catch (e) {
      error = e.toString();
    } finally {
      _isGenerating = false;
      _abortController = null;
      _lastResult = AgentOneShotResult(
        input: normalizedInput,
        content: _streamingContent,
        reasoning: _streamingReasoning,
        interrupted: interrupted,
        error: error,
        timestamp: DateTime.now(),
      );
      notifyListeners();
    }
  }

  /// 清空一次性结果展示区。
  void clearLastResult() {
    _lastResult = null;
    _streamingContent = '';
    _streamingReasoning = '';
    notifyListeners();
  }

  void _sortAgents() {
    _agents.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// 首次进入应用时自动写入一个示例智能体，方便用户快速体验。
  Future<void> _seedExampleAgentIfNeeded(List<AgentProfile> loaded) async {
    final seeded = await Storage.isAgentExampleSeeded();
    if (seeded) return;

    if (loaded.isEmpty) {
      loaded.add(
        AgentProfile.create(
          name: '翻译助手（例）',
          summary: '将非中文内容直接翻译为中文，只返回译文。',
          prompt:
              '你是一个语言翻译专家，需要将非中文语言翻译为中文，收到用户发送的内容后，直接准确地翻译为对应的中文，不要加任何多余的内容。',
        ),
      );
      await Storage.saveAgentProfiles(loaded);
    }
    await Storage.markAgentExampleSeeded();
  }
}
