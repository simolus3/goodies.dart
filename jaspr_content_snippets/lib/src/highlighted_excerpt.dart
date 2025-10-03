import 'excerpts/excerpt.dart';
import 'highlight/highlighter.dart';

/// Extracted information about all excerpts in a source snippet file.
final class ExtractedExcerpts {
  /// All excerpts in the source file.
  final List<RenderedExcerpt> excerpts;

  /// All highlighting tokens found for the source file.
  final List<HighlightToken>? tokens;

  ExtractedExcerpts({required this.excerpts, this.tokens});

  factory ExtractedExcerpts.fromJson(Map<String, Object?> json) {
    return ExtractedExcerpts(
      excerpts: [
        for (final raw in json['excerpts'] as List)
          RenderedExcerpt.fromJson(raw),
      ],
      tokens: json['tokens'] != null
          ? [
              for (final serialized in json['tokens'] as List)
                HighlightToken.fromJson(serialized),
            ]
          : null,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'tokens': switch (tokens) {
        null => null,
        final tokens => [for (final token in tokens) token.toJson()],
      },
      'excerpts': [for (final excerpt in excerpts) excerpt.toJson()],
    };
  }
}

/// A pre-rendered excerpt generated as HTML nodes by `jaspr_content_snippets`.
final class RenderedExcerpt {
  /// Line information making upo this excerpt.
  final Excerpt excerpt;

  /// The rendered HTML snippet for this excerpt.
  ///
  /// This HTML is typically a fragment of `<span>` nodes using CSS classes for
  /// highlighting. Users should wrap that in a `<pre>` and `<code>` snippet to
  /// render it.
  final String html;

  RenderedExcerpt({required this.excerpt, required this.html});

  factory RenderedExcerpt.fromJson(Map<String, Object?> json) {
    return RenderedExcerpt(
      excerpt: Excerpt.fromJson(json['excerpt'] as Map<String, Object?>),
      html: json['html'] as String,
    );
  }

  Map<String, Object?> toJson() {
    return {'html': html, 'excerpt': excerpt.toJson()};
  }
}
