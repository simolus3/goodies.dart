import 'excerpts/excerpt.dart';
import 'highlight/highlighter.dart';

final class ExtractedExcerpts {
  final List<RenderedExcerpt> excerpts;
  final List<HighlightToken>? tokens;

  ExtractedExcerpts({required this.excerpts, this.tokens});

  factory ExtractedExcerpts.fromJson(Map<String, Object?> json) {
    return ExtractedExcerpts(
      excerpts: [
        for (final raw in json['excerpts'] as List)
          RenderedExcerpt.fromJson(raw),
      ],
      tokens: [
        for (final serialized in json['tokens'] as List)
          HighlightToken.fromJson(serialized),
      ],
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

final class RenderedExcerpt {
  final Excerpt excerpt;
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
