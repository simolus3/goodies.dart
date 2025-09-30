import 'excerpts/excerpt.dart';
import 'highlight/highlighter.dart';

final class ExtractedExcerpts {
  final Map<String, Excerpt> excerpts;
  final List<HighlightToken>? tokens;

  ExtractedExcerpts({required this.excerpts, this.tokens});

  factory ExtractedExcerpts.fromJson(Map<String, Object?> json) {
    return ExtractedExcerpts(
      excerpts: {
        for (final raw in json['excerpts'] as List)
          raw['name'] as String: Excerpt.fromJson(raw),
      },
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
      'excerpts': [for (final excerpt in excerpts.values) excerpt.toJson()],
    };
  }
}
