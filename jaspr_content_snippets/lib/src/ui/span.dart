import 'dart:math';

import 'package:jaspr/jaspr.dart';
import 'package:jaspr/jaspr.dart' as jaspr;
import 'package:source_span/source_span.dart';
import 'package:syntax_highlight_lite/syntax_highlight_lite.dart' hide Color;

import '../highlight/highlighter.dart';
import '../highlight/token_type.dart';
import '../highlighted_excerpt.dart';
import '../excerpts/excerpt.dart';

/// Renders an [Excerpt] into a sequence of `<span>` elements.
///
/// This is a low-level API to render snippets. Typically, one would at least
/// want to wrap this component in a `<code><pre>` block (it relies on
/// whitespace and line-breaks being preserved).
final class ExcerptSpan extends StatelessComponent {
  final CodeRenderingOptions options;

  ExcerptSpan({super.key, required this.options});

  @override
  Component build(BuildContext context) {
    final excerpt = options.excerpt;
    final tokens = options.excerpts.tokens ?? const [];
    final source = options.file;

    final nodes = <Component>[];
    var currentToken = 0;
    ContinousRegion? last;

    Component createRawTextNode(FileSpan span, [int stripIndent = 0]) {
      if (stripIndent == 0) {
        return text(span.text);
      } else {
        // Go through the span line-by-line. If it starts at the beginning of a
        // line, drop the first [stripIndent] units.
        final file = span.file;
        final buffer = StringBuffer();

        // First line, cut of `start column - stripIndent` chars at the start
        buffer.write(
          file.getText(
            span.start.offset + max(0, stripIndent - span.start.column),
            min(file.getOffset(span.start.line + 1) - 1, span.end.offset),
          ),
        );

        for (var line = span.start.line + 1; line <= span.end.line; line++) {
          buffer.writeln();

          final endOffset = min(file.getOffset(line + 1) - 1, span.end.offset);
          final start = file.getOffset(line) + stripIndent;

          if (start < endOffset) {
            // If the span spans multiple lines and this isn't the first one, we
            // can just cut of the first chars.
            buffer.write(file.getText(start, endOffset));
          }
        }

        return text(buffer.toString());
      }
    }

    void rawText(FileSpan span, [int stripIndent = 0]) {
      nodes.add(createRawTextNode(span, stripIndent));
    }

    void styledToken(
      HighlightToken token, [
      FileSpan? span,
      int stripIndent = 0,
    ]) {
      final docsUri = token.documentationUri;
      final (classes, styles) = options.mode._classesAndStylesFor(token);

      var component = createRawTextNode(
        span ?? source.span(token.offset, token.endOffset),
        stripIndent,
      );

      if (docsUri case final uri?) {
        component = a(href: uri.toString(), [component]);
      }

      nodes.add(jaspr.span(classes: classes, styles: styles, [component]));
    }

    for (final chunk in excerpt.regions) {
      final stripIndent = options.dropIndendation
          ? chunk.indentation.length
          : 0;

      if (last != null) {
        nodes.add(options.writePlaster(excerpt, last, chunk));
      }

      // Find the first token that intersects this chunk of the excerpt.
      while (currentToken < tokens.length) {
        final current = tokens[currentToken];
        final endLine = source.getLine(current.endOffset);

        if (endLine < chunk.startLine) {
          currentToken++;
        } else {
          break;
        }
      }

      var offset = source.getOffset(chunk.startLine);

      while (currentToken < tokens.length) {
        final current = tokens[currentToken];
        final startLine = source.getLine(current.offset);
        final endLine = source.getLine(current.endOffset);

        int startOffset, endOffset;
        var lastInChunk = false;

        if (startLine >= chunk.endLineExclusive) {
          // Token no longer belongs to this chunk, skip!
          break;
        }

        // Ok, this token ends in the current chunk. Does it start there too?
        if (startLine >= chunk.startLine) {
          // It does! We don't have to cut off text from the beginning then.
          startOffset = current.offset;
        } else {
          // It doesn't, start at the start of the first line in this chunk.
          startOffset = source.getOffset(chunk.startLine);
        }

        // Raw text that potentially comes before this token.
        rawText(source.span(offset, startOffset), stripIndent);

        // Same story for the end. Does the current token exceed the chunk?
        if (endLine >= chunk.endLineExclusive) {
          endOffset = source.getLine(chunk.endLineExclusive);
          lastInChunk = true;
        } else {
          endOffset = current.endOffset;
        }

        styledToken(current, source.span(startOffset, endOffset), stripIndent);
        currentToken++;
        offset = endOffset;
        if (lastInChunk) break;
      }

      // Raw text at the end of this continous region that is not a highlight
      // region.
      rawText(
        source.span(offset, source.getOffset(chunk.endLineExclusive) - 1),
        stripIndent,
      );

      last = chunk;
    }

    // Wrap everything in a span to avoid jaspr adding whitespace:
    // https://docs.jaspr.site/concepts/components#formatting-whitespace
    return span(nodes);
  }
}

final class CodeRenderingOptions {
  /// The original contents of the snippet file.
  ///
  /// Since excerpts and highlights only store offsets, this is required to
  /// efficiently extract lines or spans of texts.
  final SourceFile file;

  /// All extracted excerpts.
  final ExtractedExcerpts excerpts;

  /// The name of the excerpt to render.
  final String name;

  /// How to apply styles (either with inline CSS or by using CSS classes named
  /// after the semantic token type).
  final SpanRenderingMode mode;

  /// Whether common indendation should be removed when rendering text.
  ///
  /// If enabled, a highlight region like:
  ///
  /// ```
  /// void myFunction() {
  ///   // #docregion test
  ///   fun1();
  ///   fun2();
  ///   // #enddocregion test
  /// }
  /// ```
  ///
  /// would be rendered like
  ///
  /// ```
  /// fun1();
  /// fun2();
  /// ```
  ///
  /// If disabled (the default), it would be rendered as
  ///
  /// ```
  ///  fun1();
  ///  fun2();
  /// ```
  final bool dropIndendation;

  final Component Function(
    Excerpt excerpt,
    ContinousRegion last,
    ContinousRegion upcoming,
  )
  writePlaster;

  Excerpt get excerpt =>
      excerpts.excerpts[name] ??
      (throw ArgumentError('Unknown excerpt: $name.'));

  CodeRenderingOptions({
    required this.file,
    required this.excerpts,
    required this.name,
    this.mode = const SpanRenderingMode.cssClasses(),
    this.dropIndendation = false,
    this.writePlaster = _defaultPlaster,
  });

  static Component _defaultPlaster(
    Excerpt excerpt,
    ContinousRegion last,
    ContinousRegion upcoming,
  ) {
    return text('\n');
  }
}

sealed class SpanRenderingMode {
  const factory SpanRenderingMode.cssClasses() = _Classes;

  const factory SpanRenderingMode.highlighter(HighlighterTheme theme) =
      _HighlighterTheme;

  (String?, Styles?) _classesAndStylesFor(HighlightToken token);
}

final class _Classes implements SpanRenderingMode {
  const _Classes();

  @override
  (String?, Styles?) _classesAndStylesFor(HighlightToken token) {
    final classes = [
      token.type.toJson(),
      if (token.modifiers case final modifiers?)
        for (final modifier in modifiers) modifier.toJson(),
    ].join(' ');

    return (classes, null);
  }
}

final class _HighlighterTheme implements SpanRenderingMode {
  final HighlighterTheme _theme;

  const _HighlighterTheme(this._theme);

  @override
  (String?, Styles?) _classesAndStylesFor(HighlightToken token) {
    // Highlighters from syntax_highlight_lite use the old TextMate scope names
    // instead of semantic tokens. A mapping is available here: https://code.visualstudio.com/api/language-extensions/semantic-highlight-guide#predefined-textmate-scope-mappings
    String ifHasModifier(
      SemanticTokenModifiers mod,
      String withMod,
      String without,
    ) {
      return token.modifiers?.contains(mod) == true ? withMod : without;
    }

    final legacyScope = switch (token.type) {
      SemanticTokenTypes.namespace => 'entity.name.namespace',
      SemanticTokenTypes.type => ifHasModifier(
        SemanticTokenModifiers.defaultLibrary,
        'support.type',
        'entity.name.type',
      ),
      SemanticTokenTypes.struct => 'storage.type.struct',
      SemanticTokenTypes.class_ => ifHasModifier(
        SemanticTokenModifiers.defaultLibrary,
        'support.class',
        'entity.name.type.clas',
      ),
      SemanticTokenTypes.interface => 'entity.name.type.interface',
      SemanticTokenTypes.enum_ => 'entity.name.type.enum',
      SemanticTokenTypes.function => ifHasModifier(
        SemanticTokenModifiers.defaultLibrary,
        'support.function',
        'entity.name.function',
      ),
      SemanticTokenTypes.method => 'entity.name.function.member',
      SemanticTokenTypes.macro => 'entity.name.function.preprocessor',
      SemanticTokenTypes.variable => ifHasModifier(
        SemanticTokenModifiers.readonly,
        'variable.other.constant',
        ifHasModifier(
          SemanticTokenModifiers.defaultLibrary,
          'support.constant',
          'variable.other.readwrite',
        ),
      ),
      SemanticTokenTypes.parameter => 'variable.parameter',
      SemanticTokenTypes.property => ifHasModifier(
        SemanticTokenModifiers.readonly,
        'variable.other.property',
        'variable.other.property',
      ),
      SemanticTokenTypes.enumMember => 'variable.other.enummember',
      SemanticTokenTypes.event => 'variable.other.event',

      _ => '',
    };

    Styles highlightStyleToJaspr(TextStyle style) {
      return Styles(
        color: Color.value(style.foreground.argb & 0x00FFFFFF),
        fontWeight: style.bold ? FontWeight.bold : null,
        fontStyle: style.italic ? FontStyle.italic : null,
        textDecoration: style.underline
            ? TextDecoration(line: TextDecorationLine.underline)
            : null,
      );
    }

    for (final scope in legacyScope.split('.').reversed) {
      if (_theme.scopes[scope] case final style?) {
        return (null, highlightStyleToJaspr(style));
      }
    }

    return (null, null);
  }
}
