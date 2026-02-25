part of 'api_service.dart';

/// 图片生成/编辑请求实现（首版支持 OpenAI Images 协议）。

/// 图片生成内部入口（text-to-image）。
Future<Map<String, dynamic>> _generateImageInternal({
  required AIProviderConfig provider,
  required String model,
  required String prompt,
  required ImageRequestMode requestMode,
  String? size,
  String? quality,
  int n = 1,
}) async {
  try {
    final normalizedPrompt = prompt.trim();
    if (normalizedPrompt.isEmpty) {
      throw Exception('提示词不能为空');
    }

    final uri = _resolveImageEndpointUri(
      provider: provider,
      requestMode: requestMode,
      operation: _imageOperationGenerate,
    );
    final headers = <String, String>{
      ..._buildImageRequestHeaders(provider),
      // 图像生成请求体是 JSON，必须显式声明 Content-Type，部分服务端否则会按空表单解析。
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final body = <String, dynamic>{
      'model': model.trim(),
      'prompt': normalizedPrompt,
      'n': n <= 0 ? 1 : n,
      if ((size ?? '').trim().isNotEmpty) 'size': size!.trim(),
      if ((quality ?? '').trim().isNotEmpty) 'quality': quality!.trim(),
    };

    AppLogger.i('ImageAPI.generate -> $uri, model=${model.trim()}');
    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      AppLogger.w(
        'ImageAPI.generate failed: status=${response.statusCode}, body=${_truncateImageResponseLog(response.body)}',
      );
      throw Exception('生图请求失败(${response.statusCode}): ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('图片生成响应格式错误');
    }

    final imageUris = await _extractImageUrisFromResponse(decoded, uri);
    if (imageUris.isEmpty) {
      throw Exception('生图响应中未包含可用图片');
    }

    final revisedPrompt = _extractRevisedPrompt(decoded);
    AppLogger.i(
      'ImageAPI.generate success: model=${model.trim()}, images=${imageUris.length}',
    );
    return <String, dynamic>{
      'imageUris': imageUris,
      'revisedPrompt': revisedPrompt,
      'operation': _imageOperationGenerate,
    };
  } catch (error, stackTrace) {
    AppLogger.e(
      'ImageAPI.generate exception: model=${model.trim()}, mode=${requestMode.name}',
      error,
      stackTrace,
    );
    rethrow;
  }
}

/// 图片编辑内部入口（image-to-image）。
Future<Map<String, dynamic>> _editImageInternal({
  required AIProviderConfig provider,
  required String model,
  required String imagePath,
  required String prompt,
  required ImageRequestMode requestMode,
  String? size,
  int n = 1,
}) async {
  try {
    final normalizedPrompt = prompt.trim();
    if (normalizedPrompt.isEmpty) {
      throw Exception('编辑提示词不能为空');
    }
    final normalizedPath = imagePath.trim();
    if (normalizedPath.isEmpty) {
      throw Exception('请先选择待编辑图片');
    }
    final inputFile = File(normalizedPath);
    if (!await inputFile.exists()) {
      throw Exception('待编辑图片不存在: $normalizedPath');
    }

    final uri = _resolveImageEndpointUri(
      provider: provider,
      requestMode: requestMode,
      operation: _imageOperationEdit,
    );
    final headers = <String, String>{
      ..._buildImageRequestHeaders(provider),
      'Accept': 'application/json',
    };
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(headers)
      ..fields['model'] = model.trim()
      ..fields['prompt'] = normalizedPrompt
      ..fields['n'] = (n <= 0 ? 1 : n).toString()
      ..files.add(await http.MultipartFile.fromPath('image', normalizedPath));
    if ((size ?? '').trim().isNotEmpty) {
      request.fields['size'] = size!.trim();
    }

    AppLogger.i('ImageAPI.edit -> $uri, model=${model.trim()}');
    final streamed = await request.send();
    final responseText = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      AppLogger.w(
        'ImageAPI.edit failed: status=${streamed.statusCode}, body=${_truncateImageResponseLog(responseText)}',
      );
      throw Exception('图片编辑请求失败(${streamed.statusCode}): $responseText');
    }

    final decoded = jsonDecode(responseText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('图片编辑响应格式错误');
    }

    final imageUris = await _extractImageUrisFromResponse(decoded, uri);
    if (imageUris.isEmpty) {
      throw Exception('图片编辑响应中未包含可用图片');
    }

    final revisedPrompt = _extractRevisedPrompt(decoded);
    AppLogger.i(
      'ImageAPI.edit success: model=${model.trim()}, images=${imageUris.length}',
    );
    return <String, dynamic>{
      'imageUris': imageUris,
      'revisedPrompt': revisedPrompt,
      'operation': _imageOperationEdit,
    };
  } catch (error, stackTrace) {
    AppLogger.e(
      'ImageAPI.edit exception: model=${model.trim()}, mode=${requestMode.name}',
      error,
      stackTrace,
    );
    rethrow;
  }
}

const String _imageOperationGenerate = 'generate';
const String _imageOperationEdit = 'edit';

/// 控制日志体积，避免响应体过大导致日志污染。
String _truncateImageResponseLog(String rawBody) {
  const maxLength = 1000;
  if (rawBody.length <= maxLength) return rawBody;
  return '${rawBody.substring(0, maxLength)}...';
}

/// 解析图像接口地址（当前支持 OpenAI Images 协议族）。
Uri _resolveImageEndpointUri({
  required AIProviderConfig provider,
  required ImageRequestMode requestMode,
  required String operation,
}) {
  final base = _normalizeBaseUrl(provider.baseUrl);
  if (base.isEmpty) {
    throw Exception('Provider Base URL 为空，无法请求图片接口');
  }

  final effectiveMode = _resolveEffectiveImageMode(
    provider: provider,
    requestMode: requestMode,
    operation: operation,
  );
  final path = switch (effectiveMode) {
    ImageRequestMode.openaiImagesGenerate => '/images/generations',
    ImageRequestMode.openaiImagesEdit => '/images/edits',
    ImageRequestMode.inheritProvider => throw Exception('未解析出有效图片协议'),
  };
  return _buildUri(base, path);
}

/// 计算最终图像协议模式（支持 Provider 默认继承 + 模型显式覆盖）。
ImageRequestMode _resolveEffectiveImageMode({
  required AIProviderConfig provider,
  required ImageRequestMode requestMode,
  required String operation,
}) {
  if (requestMode != ImageRequestMode.inheritProvider) {
    return requestMode;
  }
  // 继承 Provider 时，当前仅在 OpenAI Chat 语义下映射到 OpenAI Images。
  if (provider.requestMode == RequestMode.openaiChat) {
    return operation == _imageOperationEdit
        ? ImageRequestMode.openaiImagesEdit
        : ImageRequestMode.openaiImagesGenerate;
  }
  throw Exception(
    '当前 Provider 请求模式(${provider.requestMode.name})不支持继承为图片协议，请为模型单独配置图像协议',
  );
}

/// 构建图像接口请求头。
Map<String, String> _buildImageRequestHeaders(AIProviderConfig provider) {
  final headers = <String, String>{};
  final apiKey = (provider.apiKey ?? '').trim();
  if (apiKey.isNotEmpty) {
    headers['Authorization'] = 'Bearer $apiKey';
  }
  return headers;
}

/// 从图片响应中抽取可展示图片地址（URL 或落地后的本地路径）。
Future<List<String>> _extractImageUrisFromResponse(
  Map<String, dynamic> payload,
  Uri? requestUri
) async {
  final data = payload['data'];
  if (data is! List || data.isEmpty) return const <String>[];
  final imageUris = <String>[];
  for (final item in data) {
    if (item is! Map) continue;
    final url = item['url']?.toString().trim();
    if (url != null && url.isNotEmpty) {
      imageUris.add(_normalizeRemoteImageUrl(url, requestUri: requestUri));
      continue;
    }
    final b64 = item['b64_json']?.toString().trim();
    if (b64 != null && b64.isNotEmpty) {
      final path = await _writeBase64ImageToTempFile(b64);
      if (path != null) {
        imageUris.add(path);
      }
    }
  }
  return imageUris;
}

/// 规范化服务端返回的图片 URL，兼容“缺少协议头”的返回格式。
String _normalizeRemoteImageUrl(String rawUrl, {Uri? requestUri}) {
  final value = rawUrl.trim();
  if (value.isEmpty) return value;
  final parsed = Uri.tryParse(value);
  if (parsed != null && parsed.hasScheme) {
    return value;
  }

  final scheme = (requestUri?.scheme.isNotEmpty ?? false)
      ? requestUri!.scheme
      : 'https';

  // `//host/path` -> `https://host/path`
  if (value.startsWith('//')) {
    return '$scheme:$value';
  }

  // `/path/to/image.png` -> `https://host/path/to/image.png`
  if (value.startsWith('/') && requestUri != null) {
    return '${requestUri.scheme}://${requestUri.host}${requestUri.hasPort ? ':${requestUri.port}' : ''}$value';
  }

  // `host/path` -> `https://host/path`
  final looksLikeHostPath = RegExp(
    r'^[A-Za-z0-9.-]+\.[A-Za-z]{2,}(:\d+)?/.+',
  ).hasMatch(value);
  if (looksLikeHostPath) {
    return '$scheme://$value';
  }
  return value;
}

/// 读取响应中的 revised_prompt（若有）。
String? _extractRevisedPrompt(Map<String, dynamic> payload) {
  final data = payload['data'];
  if (data is! List || data.isEmpty) return null;
  final first = data.first;
  if (first is! Map) return null;
  final revised = first['revised_prompt']?.toString().trim();
  if (revised == null || revised.isEmpty) return null;
  return revised;
}

/// 将 `b64_json` 图片写入临时文件并返回路径。
Future<String?> _writeBase64ImageToTempFile(String base64Payload) async {
  try {
    final bytes = base64Decode(base64Payload);
    final dir = await getTemporaryDirectory();
    final fileName =
        'nowchat_img_${DateTime.now().microsecondsSinceEpoch}_${bytes.length}.png';
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (error, stackTrace) {
    AppLogger.e('写入 base64 图片失败', error, stackTrace);
    return null;
  }
}
