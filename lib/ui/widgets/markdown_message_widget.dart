import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:highlight/highlight.dart' as hi;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

class MarkdownMessageWidget extends StatelessWidget {
  final String data;
  const MarkdownMessageWidget({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final baseText = TextStyle(
      fontSize: 16,
      color: color.onSurface,
      height: 1.65,
      letterSpacing: 0.1,
    );
    return MarkdownBody(
      data: data,
      onTapLink: (text, href, title) {
        if (href != null) {
          launchUrl(Uri.parse(href));
        }
      },
      builders: {
        'code': CodeBlockBuilder(context),
        'hr': HorizontalRuleBuilder(context),
      },
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: baseText,
        h1: baseText.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
        h2: baseText.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
        h3: baseText.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
        strong: baseText.copyWith(fontWeight: FontWeight.w700),
        em: baseText.copyWith(fontStyle: FontStyle.italic),
        listBullet: baseText.copyWith(fontSize: 15),
        listIndent: 22,
        codeblockDecoration: BoxDecoration(
          color: color.surfaceContainerHighest.withAlpha(150),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.outline.withAlpha(70)),
        ),
        codeblockPadding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          color: color.onSurfaceVariant,
        ),
        a: TextStyle(
          color: color.primary,
          decoration: TextDecoration.underline,
          decorationColor: color.primary.withAlpha(160),
          decorationThickness: 1.4,
        ),
        blockquote: TextStyle(
          color: color.onSurfaceVariant,
          fontStyle: FontStyle.italic,
          height: 1.6,
        ),
        blockquotePadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        blockquoteDecoration: BoxDecoration(
          color: color.secondaryContainer.withAlpha(90),
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: color.secondary, width: 3)),
        ),
        tableBorder: TableBorder.all(color: color.outline.withAlpha(120)),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
        tableHead: baseText.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: color.onSurface,
        ),
        tableBody: baseText.copyWith(fontSize: 14),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              width: 1.2,
              color: color.outlineVariant.withAlpha(160),
            ),
          ),
        ),
        img: TextStyle(fontSize: 0),
      ),
    );
  }
}

class HorizontalRuleBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  HorizontalRuleBuilder(this.context);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final color = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          width: 170,
          height: 2,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              colors: [
                color.outline.withAlpha(20),
                color.outline.withAlpha(150),
                color.outline.withAlpha(20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CodeBlockBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  CodeBlockBuilder(this.context);

  static const Map<String, String> _languageAliases = {
    'js': 'javascript',
    'ts': 'typescript',
    'py': 'python',
    'sh': 'bash',
    'shell': 'bash',
    'c++': 'cpp',
    'c#': 'cs',
    'objective-c': 'objectivec',
  };

  String _normalizeLanguage(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return '';
    return _languageAliases[value] ?? value;
  }

  String _languageFromClassAttr(String? classAttr) {
    final cls = (classAttr ?? '').trim();
    if (cls.isEmpty) return '';
    final parts = cls.split(RegExp(r'\s+'));
    for (final part in parts) {
      if (part.startsWith('language-')) {
        return _normalizeLanguage(part.substring('language-'.length));
      }
    }
    return _normalizeLanguage(parts.first);
  }

  String _resolveLanguage(md.Element element) {
    final fromSelf = _languageFromClassAttr(element.attributes['class']);
    if (fromSelf.isNotEmpty) return fromSelf;
    return '';
  }

  String _autoDetectLanguage(String code) {
    try {
      final result = hi.highlight.parse(code, autoDetection: true);
      return _normalizeLanguage(result.language ?? '');
    } catch (_) {
      return '';
    }
  }

  Map<String, TextStyle> _highlightThemeNoBg(ColorScheme color) {
    return githubTheme.map((key, style) {
      return MapEntry(
        key,
        style.copyWith(
          backgroundColor: Colors.transparent,
          fontFamily: 'monospace',
          fontSize: 13.5,
        ),
      );
    });
  }

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
    final rawCode = _extractText(element);
    final code = rawCode.trimRight();
    if (code.isEmpty) return null;

    final color = Theme.of(context).colorScheme;
    final language = _resolveLanguage(element);
    final effectiveLanguage =
        language.isNotEmpty ? language : _autoDetectLanguage(code);
    final isMultiline = rawCode.contains('\n') || language.isNotEmpty;

    if (!isMultiline) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.primaryContainer.withAlpha(120),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          code,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13.5,
            color: color.onPrimaryContainer,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: color.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.outline.withAlpha(65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Row(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.primaryContainer.withAlpha(120),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    language.isNotEmpty ? language : 'code',
                    style: TextStyle(
                      fontSize: 11,
                      color: color.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    icon: Icon(
                      Icons.copy,
                      size: 16,
                      color: color.onSurfaceVariant,
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
              top: 2,
              bottom: 12,
            ),
            child: HighlightView(
              code,
              language:
                  effectiveLanguage.isNotEmpty
                      ? effectiveLanguage
                      : 'plaintext',
              theme: _highlightThemeNoBg(color),
              padding: EdgeInsets.zero,
              textStyle: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13.5,
                height: 1.55,
                color: color.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
