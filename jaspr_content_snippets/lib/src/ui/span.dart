import 'dart:math';

import 'package:jaspr/jaspr.dart';
import 'package:jaspr/jaspr.dart' as jaspr;
import 'package:source_span/source_span.dart';

import '../highlight/highlighter.dart';
import '../excerpts/excerpt.dart';
import 'options.dart';

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
      final (classes, styles) = options.mode.classesAndStylesFor(token);

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
