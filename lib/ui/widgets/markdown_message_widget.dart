import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:highlight/highlight.dart' as hi;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

/// MarkdownMessageWidget 组件。
class MarkdownMessageWidget extends StatelessWidget {
  final String data;
  final bool selectable;
  const MarkdownMessageWidget({
    super.key,
    required this.data,
    this.selectable = false,
  });

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
      selectable: selectable,
      onTapLink: (text, href, title) {
        if (href != null) {
          launchUrl(Uri.parse(href));
        }
      },
      builders: {
        'latex': LatexElementBuilder(context, displayMode: false),
        'latex_block': LatexElementBuilder(context, displayMode: true),
        'code': CodeBlockBuilder(context),
        'hr': HorizontalRuleBuilder(context),
      },
      inlineSyntaxes: [LatexBlockSyntax(), LatexInlineSyntax()],
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

/// 执行 _extractNodeText 逻辑。
String _extractNodeText(md.Node node) {
  if (node is md.Text) {
    return node.text;
  } else if (node is md.Element) {
    final buffer = StringBuffer();
    for (final child in node.children ?? <md.Node>[]) {
      buffer.write(_extractNodeText(child));
    }
    return buffer.toString();
  }
  return '';
}

/// LatexBlockSyntax 类型定义。
class LatexBlockSyntax extends md.InlineSyntax {
  LatexBlockSyntax()
    : super(r'(?<!\\)\$\$([\s\S]+?)(?<!\\)\$\$', startCharacter: 36);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final expression = match.group(1);
    if (expression == null || expression.trim().isEmpty) {
      parser.addNode(md.Text(match.group(0)!));
      return true;
    }
    parser.addNode(md.Element.text('latex_block', expression));
    return true;
  }
}

/// LatexInlineSyntax 类型定义。
class LatexInlineSyntax extends md.InlineSyntax {
  LatexInlineSyntax()
    : super(r'(?<!\\)\$([^\$\n]+?)(?<!\\)\$', startCharacter: 36);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final expression = match.group(1);
    if (expression == null || expression.trim().isEmpty) {
      parser.addNode(md.Text(match.group(0)!));
      return true;
    }
    parser.addNode(md.Element.text('latex', expression));
    return true;
  }
}

/// LatexElementBuilder 类型定义。
class LatexElementBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  final bool displayMode;

  LatexElementBuilder(this.context, {required this.displayMode});

  String _normalizeExpression(String source) {
    return source.replaceAll(r'\$', r'$').trim();
  }

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final expression = _normalizeExpression(_extractNodeText(element));
    if (expression.isEmpty) return null;

    final color = Theme.of(context).colorScheme;
    final textStyle = TextStyle(
      color: color.onSurface,
      fontSize: displayMode ? 17 : 16,
      height: 1.4,
    );

    final widget = Math.tex(
      expression,
      mathStyle: displayMode ? MathStyle.display : MathStyle.text,
      textStyle: textStyle,
      onErrorFallback:
          (_) =>
              Text(expression, style: textStyle.copyWith(color: color.error)),
    );

    if (!displayMode) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
        child: widget,
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.surfaceContainerHighest.withAlpha(110),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.outline.withAlpha(60)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: widget,
      ),
    );
  }
}

/// HorizontalRuleBuilder 类型定义。
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

/// CodeBlockBuilder 类型定义。
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
    return _extractNodeText(node);
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
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Clipboard.setData(ClipboardData(text: code));
            _showClosableSnackBar('已复制代码');
          },
          child: Container(
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
                      _showClosableSnackBar('已复制到剪贴板');
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
