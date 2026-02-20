import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:now_chat/util/app_logger.dart';

/// 图片预览页面：支持查看大图、基础信息，并保存到系统相册。
class ImagePreviewPage extends StatefulWidget {
  final Uri imageUri;
  final String title;

  const ImagePreviewPage({
    super.key,
    required this.imageUri,
    this.title = '图片预览',
  });

  @override
  State<ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<ImagePreviewPage> {
  /// 原生媒体桥接：用于把字节流写入 Android 系统相册。
  static const MethodChannel _mediaChannel = MethodChannel(
    'nowchat/media_bridge',
  );

  Uint8List? _imageBytes;
  int? _imageWidth;
  int? _imageHeight;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  /// 读取图片字节并解析分辨率。
  Future<void> _loadImage() async {
    try {
      final bytes = await _readImageBytes(widget.imageUri);
      final dimensions = await _decodeImageDimensions(bytes);
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageWidth = dimensions.$1;
        _imageHeight = dimensions.$2;
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      AppLogger.e('加载图片预览失败', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.toString();
      });
    }
  }

  /// 保存图片到系统相册（Android MediaStore）。
  Future<void> _saveToGallery() async {
    final bytes = _imageBytes;
    if (bytes == null || _isSaving) return;
    if (!Platform.isAndroid) {
      _showClosableSnackBar('当前平台暂不支持保存到系统相册');
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      final mimeType = _guessMimeType(bytes);
      final fileName = _buildFileName(mimeType);
      final result = await _mediaChannel.invokeMethod<dynamic>(
        'saveImageToGallery',
        <String, dynamic>{
          'bytes': bytes,
          'mimeType': mimeType,
          'fileName': fileName,
        },
      );
      final uri = (result is Map) ? (result['uri']?.toString() ?? '') : '';
      if (!mounted) return;
      _showClosableSnackBar(
        uri.isEmpty ? '保存成功，已写入相册' : '保存成功：$uri',
      );
    } catch (error, stackTrace) {
      AppLogger.e('保存图片到相册失败', error, stackTrace);
      if (!mounted) return;
      _showClosableSnackBar('保存失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  /// 读取图片字节：支持 http(s)、file、data URI、本地绝对路径。
  Future<Uint8List> _readImageBytes(Uri uri) async {
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('网络图片加载失败(${response.statusCode})');
      }
      return response.bodyBytes;
    }
    if (uri.scheme == 'file') {
      return File(uri.toFilePath()).readAsBytes();
    }
    if (uri.scheme == 'data') {
      final raw = uri.toString();
      final marker = raw.indexOf(',');
      if (marker <= 0) {
        throw Exception('不支持的数据 URI');
      }
      final payload = raw.substring(marker + 1);
      return Uint8List.fromList(base64Decode(payload));
    }
    if (uri.scheme.isEmpty && uri.path.startsWith('/')) {
      return File(uri.path).readAsBytes();
    }
    throw Exception('不支持的图片地址: $uri');
  }

  /// 解码图片分辨率（宽、高）。
  Future<(int, int)> _decodeImageDimensions(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    return (image.width, image.height);
  }

  /// 基于文件头推断 mimeType，避免依赖 URL 后缀。
  String _guessMimeType(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return 'image/png';
  }

  /// 生成默认保存文件名。
  String _buildFileName(String mimeType) {
    final ext = switch (mimeType) {
      'image/jpeg' => 'jpg',
      'image/webp' => 'webp',
      _ => 'png',
    };
    return 'nowchat_${DateTime.now().millisecondsSinceEpoch}.$ext';
  }

  /// 将字节数格式化为可读体积文本。
  String _formatByteCount(int length) {
    if (length < 1024) return '$length B';
    final kb = length / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }

  void _showClosableSnackBar(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: '关闭',
          onPressed: messenger.hideCurrentSnackBar,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed:
                (_imageBytes == null || _isSaving || _isLoading)
                    ? null
                    : _saveToGallery,
            tooltip: _isSaving ? '正在保存...' : '保存到相册',
            icon:
                _isSaving
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.save_alt_outlined),
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (_isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_error != null) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '图片加载失败',
                    style: TextStyle(
                      color: color.error,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(_error!),
                ],
              ),
            );
          }
          final bytes = _imageBytes!;
          final previewBackground = Color.lerp(
            color.surface,
            color.inverseSurface,
            0.86,
          )!;
          return Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Container(
                      color: previewBackground,
                      child: InteractiveViewer(
                        minScale: 1.0,
                        maxScale: 6.0,
                        boundaryMargin: const EdgeInsets.all(300),
                        clipBehavior: Clip.none,
                        child: SizedBox(
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          child: Container(
                            color: previewBackground,
                            alignment: Alignment.center,
                            child: Image.memory(bytes, fit: BoxFit.contain),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                decoration: BoxDecoration(
                  color: color.surface,
                  border: Border(top: BorderSide(color: color.outlineVariant)),
                ),
                child: DefaultTextStyle(
                  style: TextStyle(color: color.onSurfaceVariant, fontSize: 12.5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '分辨率: ${_imageWidth ?? '-'} x ${_imageHeight ?? '-'}',
                      ),
                      const SizedBox(height: 4),
                      Text('大小: ${_formatByteCount(bytes.length)}'),
                      const SizedBox(height: 4),
                      const Text('保存位置: 系统相册 / Pictures/NowChat'),
                      const SizedBox(height: 6),
                      SelectableText(
                        '来源: ${widget.imageUri}',
                        style: TextStyle(color: color.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
