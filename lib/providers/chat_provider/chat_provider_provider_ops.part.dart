part of '../chat_provider.dart';

/// ChatProviderProviderOps 扩展方法集合。
extension ChatProviderProviderOps on ChatProvider {
  /// 刷新指定提供方的模型列表与模型元信息。
  Future<void> refreshConfigModels(
    String id,
    List<String> models, {
    Map<String, String>? modelRemarks,
    Map<String, ModelFeatureOptions>? modelCapabilities,
  }) async {
    final provider = getProviderById(id);
    if (provider == null) return;
    provider.updateConfig(
      models: models,
      modelRemarks: modelRemarks ?? provider.modelRemarks,
      modelCapabilities: modelCapabilities ?? provider.modelCapabilities,
    );
    await _saveProviders();
    _notifyStateChanged();
  }

  /// 创建提供方。
  Future<void> createNewProvider(AIProviderConfig provider) async {
    _providers.insert(0, provider);
    await _saveProviders();
    _notifyStateChanged();
  }

  /// 删除提供方。
  Future<void> deleteProvider(String id) async {
    _providers.removeWhere((p) => p.id == id);
    await _saveProviders();
    _notifyStateChanged();
  }

  /// 更新提供方配置。
  Future<void> updateProvider(
    String providerId, {
    String? name,
    ProviderType? type,
    RequestMode? requestMode,
    String? baseUrl,
    String? urlPath,
    String? apiKey,
    List<String>? models,
    Map<String, String>? modelRemarks,
    Map<String, ModelFeatureOptions>? modelCapabilities,
  }) async {
    final provider = getProviderById(providerId);
    if (provider == null) return;
    provider.updateConfig(
      name: name,
      type: type,
      requestMode: requestMode,
      baseUrl: baseUrl,
      apiKey: apiKey,
      urlPath: urlPath,
      models: models,
      modelRemarks: modelRemarks,
      modelCapabilities: modelCapabilities,
    );
    await _saveProviders();
    _notifyStateChanged();
  }

  /// 调用 API 拉取模型列表。
  Future<List<String>> fetchModels(
    AIProviderConfig provider,
    String baseUrl,
    String apiKey,
  ) async {
    return ApiService.fetchModels(provider, baseUrl, apiKey);
  }

  /// 持久化提供方列表到本地。
  Future<void> _saveProviders() async {
    await Storage.saveProviders(_providers);
  }
}
