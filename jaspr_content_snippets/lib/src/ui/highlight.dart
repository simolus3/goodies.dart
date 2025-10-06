import 'package:jaspr/server.dart';
import 'package:source_span/source_span.dart';

import '../excerpts/excerpt.dart';
import '../highlight/highlighter.dart';
import 'options.dart';
import 'span.dart';

/// A [StatelessComponent] rendering a source file (given as a [String]) for a
/// supported language.
///
/// Like [ExcerptSpan], this just renders the underlying nodes and needs to be
/// wrapped a `<pre>` and `<code>` block to be displayed properly.
final class HighlightBlock extends StatelessComponent {
  final String source;
  final String language;

  HighlightBlock({super.key, required this.source, required this.language});

  @override
  Component build(BuildContext context) {
    final highlighter = SyntaxOnlyHighlighter.builtin('.$language');
    var tokens = highlighter?.highlightWithoutContext(source);
    if (tokens != null) {
      tokens.sort(HighlightToken.offsetLengthPrioritySort);
      tokens = HighlightToken.splitOverlappingTokens(tokens).toList();
    } else {
      tokens = const [];
    }

    final sourceFile = SourceFile.fromString(source);

    final options = CodeRenderingOptions(
      file: sourceFile,
      excerpt: Excerpt('(full)', [ContinousRegion(0, sourceFile.lines - 1)]),
      tokens: tokens,
    );

    return ExcerptSpan(options: options);
  }
}
