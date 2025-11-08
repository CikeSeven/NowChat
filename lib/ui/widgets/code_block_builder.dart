import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// 支持在构建器中传入 context，以便使用主题与 ScaffoldMessenger
class CodeBlockBuilder1 extends MarkdownElementBuilder {
  final BuildContext context;
  CodeBlockBuilder1(this.context);

  String _extractText(md.Node node) {
    if (node is md.Text) {
      return node.text;
    } else if (node is md.Element) {
      final buffer = StringBuffer();
      for (final child in node.children ?? <md.Node>[]) {
        buffer.write(_extractText(child));
      }
      return buffer.toString();
    }
    return '';
  }

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final code = _extractText(element).trim();
    if (code.isEmpty) return null;

    final color = Theme.of(context).colorScheme;

    // 判断是否为多行代码块
    final isMultiline = code.contains('\n') || element.attributes['class']?.contains('language-') == true;

    if (!isMultiline) {
      // 单行内联代码 → 不加复制按钮
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.surfaceContainerHighest.withAlpha(130),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          code,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            color: color.onSurfaceVariant,
          ),
        ),
      );
    }

    //多行代码块 → 带复制按钮
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: color.surfaceContainerHighest.withAlpha(130),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 12),
            child: SelectableText(
              code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                color: color.onSurfaceVariant,
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: IconButton(
              icon: Icon(
                Icons.copy,
                size: 18,
                color: color.onSurfaceVariant.withAlpha(220),
              ),
              tooltip: '复制代码',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
              },
            ),
          ),
        ],
      ),
    );
  }
}