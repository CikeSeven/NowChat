import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

class MarkdownMessageWidget extends StatelessWidget {
  final String data;
  const MarkdownMessageWidget({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return MarkdownBody(
      data: data,
      onTapLink: (text, href, title) {
        if (href != null) {
          launchUrl(Uri.parse(href));
        }
      },
      builders: {'code': CodeBlockBuilder(context)},
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: TextStyle(fontSize: 16, color: color.onSurface, height: 1.45),
        listBullet: TextStyle(fontSize: 16, color: color.onSurface),
        codeblockDecoration: BoxDecoration(
          color: color.surfaceContainerHighest.withAlpha(130),
          borderRadius: BorderRadius.circular(10),
        ),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 15,
          color: color.onSurfaceVariant,
        ),
        a: TextStyle(
          color: color.primary,
          decoration: TextDecoration.underline,
        ),
        blockquote: TextStyle(
          color: color.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
        img: TextStyle(fontSize: 0),
      ),
    );
  }
}

class CodeBlockBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  CodeBlockBuilder(this.context);

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
    final language =
        element.attributes['class']?.replaceFirst('language-', '') ?? '';
    final isMultiline =
        code.contains('\n') ||
        element.attributes['class']?.contains('language-') == true;

    if (!isMultiline) {
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
            fontSize: 15,
            color: color.onSurfaceVariant,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: color.surfaceContainerHighest.withAlpha(130),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16),
            child: Row(
              children: [
                Text(
                  language.isNotEmpty ? language : 'code',
                  style: TextStyle(
                    fontSize: 12,
                    color: color.onSurfaceVariant.withAlpha(180),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 22,
                  height: 22,
                  child: IconButton(
                    icon: Icon(
                      Icons.copy,
                      size: 18,
                      color: color.onSurfaceVariant.withAlpha(220),
                    ),
                    tooltip: '复制代码',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(
              left: 12,
              right: 12,
              top: 8,
              bottom: 12,
            ),
            child: HighlightView(
              code,
              language: language,
              theme: githubTheme,
              padding: EdgeInsets.zero,
              textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}
