import 'package:flutter/material.dart';
import 'package:now_chat/core/models/ai_provider_config.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';

class EditProviderPage extends StatefulWidget {
  final String providerId;
  const EditProviderPage({super.key, required this.providerId});
  @override
  State<EditProviderPage> createState() => _EditProviderPageState();
}

class _EditProviderPageState extends State<EditProviderPage> {


    List<String> _fetchedModels = [];
    bool _loadingModels = false;
    String? _loadError;
  
    late AIProviderConfig _config;
    late TextEditingController _nameController;
    late TextEditingController _baseUrlController;
    late TextEditingController _urlPathController;
    late TextEditingController _apiKeyController;

      // 控制key显示/隐藏
    bool _keyObscure = true;

    @override
    void initState() {
      super.initState();
      
      final chatProvider = context.read<ChatProvider>();

      final exsiting = chatProvider.getProviderById(widget.providerId);
      _config = exsiting ?? AIProviderConfig.newCustom();

      _nameController = TextEditingController(text: _config.name);
      _baseUrlController = TextEditingController(text: _config.baseUrl);
      _urlPathController = TextEditingController(text: _config.urlPath);
      _apiKeyController = TextEditingController(text: _config.apiKey);


      _nameController.addListener(() => setState(() {}));
      _baseUrlController.addListener(() => setState(() {}));
      _urlPathController.addListener(() => setState(() {}));
      _apiKeyController.addListener(() => setState(() {}));
    }

    @override
    void dispose() {
      _nameController.dispose();
      _baseUrlController.dispose();
      _urlPathController.dispose();
      _apiKeyController.dispose();
      super.dispose();
    }

  @override
  Widget build(BuildContext context) {

    final chatProvider = context.watch<ChatProvider>();
    final color = Theme.of(context).colorScheme;

    bool canSave = _nameController.text.trim().isNotEmpty &&
                 _baseUrlController.text.trim().isNotEmpty &&
                 _urlPathController.text.trim().isNotEmpty;

    void save() {
      chatProvider.updateProvider(
        widget.providerId,
        name: _nameController.text.trim(),
        type: _config.type,
        baseUrl: _baseUrlController.text.trim(),
        urlPath: _urlPathController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        models: _config.models
      );
      Navigator.of(context).pop();
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 自定义顶部栏（左 ×，右 ✓）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.close, color: color.primary),
                    onPressed: () => Navigator.of(context).pop(), // 取消，不返回数据
                  ),
                  Text(
                    "编辑API信息",
                    style: TextStyle(fontSize: 16),
                  ),
                  IconButton(
                    icon: Icon(Icons.check, color: canSave ? color.primary : color.onSurfaceVariant.withAlpha(135)),
                    onPressed: canSave ? save : null,
                  ),
                ],
              ),
            ),
            Divider(height: 1),
            // 编辑区域
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                style: TextStyle(fontSize: 14),
                controller: _nameController,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: "API名称",
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 8)
                ),
                autofocus: true,
                maxLines: 1,
              ),
            ),
            // 主机地址
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: TextField(
                      style: TextStyle(fontSize: 14),
                      controller: _baseUrlController,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: "API主机地址",
                        hintText: _config.baseUrl,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8)
                      ),
                      autofocus: true,
                      maxLines: 1,
                    ),
                  ),
                  if (_config.type.allowEditPath)
                  Expanded(
                    flex: 3,
                    child: Container(
                      padding: EdgeInsets.only(left: 10),
                      child: TextField(
                        style: TextStyle(fontSize: 14),
                        controller: _urlPathController,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: "API路径",
                          hintText: _config.baseUrl,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8)
                        ),
                        autofocus: true,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 6,),
            // 地址预览文本
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                "${_baseUrlController.text.trim()}${_urlPathController.text.trim()}",
                style: TextStyle(
                  fontSize: 12,
                ),
              ),
            ),

            SizedBox(height: 6,),

            // API Key
            if (_config.type.requiresApiKey)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: TextFormField(
                  style: TextStyle(fontSize: 14),
                  controller: _apiKeyController,
                  obscureText: _keyObscure,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: "API Key *",
                    hintText: "输入你的 API 密钥",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    suffixIcon: IconButton(
                      icon: Icon(_keyObscure ? Icons.visibility_off : Icons.visibility,),
                      onPressed: () {
                        setState(() {
                          _keyObscure = !_keyObscure;
                        });
                      },
                    ),
                  ),
                  validator: (v) => v!.trim().isEmpty ? '请输入 API Key' : null,
                ),
              ),
            
            _buildModelListSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildModelListSection(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    "模型列表",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: TextButton.icon(
                    icon: Icon(
                      Icons.refresh,
                      size: 18,
                      color: _loadingModels || _baseUrlController.text.trim().isEmpty
                          ? colors.onSurface.withAlpha(120)
                          : colors.primary,
                    ),
                    label: Text(
                      _loadingModels ? "正在获取..." : "获取模型",
                      style: TextStyle(
                        color: _loadingModels || _baseUrlController.text.trim().isEmpty
                            ? colors.onSurface.withAlpha(120)
                            : colors.primary,
                      ),
                    ),
                    onPressed: _loadingModels || _baseUrlController.text.trim().isEmpty
                        ? null // 禁用点击
                        : () async {
                            setState(() {
                              _loadingModels = true;
                              _loadError = null;
                              _fetchedModels.clear();
                            });
                  
                            try {
                              final models = await chatProvider.fetchModels(_config, _baseUrlController.text.trim(), _apiKeyController.text.trim());
                              setState(() {
                                _fetchedModels = models;
                              });
                            } catch (e) {
                              setState(() {
                                _loadError = e.toString();
                              });
                            } finally {
                              setState(() {
                                _loadingModels = false;
                              });
                            }
                          },
                    style: TextButton.styleFrom(
                      foregroundColor: _loadingModels
                          ? colors.onSurface.withAlpha(120)
                          : colors.primary,
                      disabledForegroundColor: colors.onSurface.withAlpha(80),
                      padding: EdgeInsets.symmetric(horizontal: 12)
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 12),
                  child: Card(
                    elevation: 0.1,
                    color: colors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "当前模型",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (_config.models.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                "暂无模型",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.outline,
                                ),
                              ),
                            )
                          else
                            ..._config.models.map(
                              (model) => _buildModelListItem(
                                model,
                                () {
                                  setState(() {
                                      _config.models.remove(model);
                                    });
                                    chatProvider.refreshConfigModels(
                                        widget.providerId, _config.models);
                                },
                              colors.primaryContainer.withAlpha(150),
                              "移除模型",
                              Icon(Icons.remove_circle_outline, size: 20, color: colors.error),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                // -----------------------
                // 可添加模型 / 加载状态
                // -----------------------
                if(_fetchedModels.isNotEmpty || _loadingModels || _loadError != null) Container(
                  margin: EdgeInsets.symmetric(horizontal: 12),
                  child: Card(
                    elevation: 0.1,
                    color: colors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "可添加模型",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                  
                          if (_loadingModels)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: colors.primary,
                                ),
                              ),
                            )
                          else if (_loadError != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                "加载失败：$_loadError",
                                style: TextStyle(color: colors.error, fontSize: 13),
                              ),
                            )
                          else if (_fetchedModels.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                "暂无可添加模型",
                                style: TextStyle(color: colors.outline, fontSize: 13),
                              ),
                            )
                          else
                            ..._fetchedModels
                                .where((m) => !_config.models.contains(m))
                                .map(
                              (model) => 
                              _buildModelListItem(
                                model,
                                () {
                                  setState(() {
                                      _config.models.add(model);
                                    });
                                    chatProvider.refreshConfigModels(
                                        widget.providerId, _config.models);
                                },
                                colors.surfaceContainer,
                                "添加模型",
                                Icon(Icons.add_circle_outline, size: 20, color: colors.primary),
                              )
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

  }

  Widget _buildModelListItem(
    String model,
    VoidCallback onPressed,
    Color color,
    String tooltip,
    Icon icon,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: color,
      ),
      margin: EdgeInsets.symmetric(vertical: 2,),
      padding: EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        children: [
          Text(
            model,
            style: TextStyle(color: colors.onSurface),
          ),
          Spacer(),
          SizedBox(
            width: 22,
            height: 22,
            child: IconButton(
              padding: EdgeInsets.zero, // 去掉内边距
              constraints: const BoxConstraints(), // 去掉默认最小尺寸
              icon: icon,
              tooltip: tooltip,
              onPressed: onPressed,
            ),
          ),
        ],
      ),
    );
  }

}



