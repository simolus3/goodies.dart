import 'package:jaspr/server.dart';
import 'package:source_span/source_span.dart';

import '../excerpts/excerpt.dart';
import '../highlight/highlighter.dart';

final class UnresolvedRenderingOptions {
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

  /// A comonent for rendering the empty snippet between two highlight regions.
  ///
  /// For instance, given a snippet like
  ///
  /// ```dart
  /// // #docregion outline
  /// class MyCoolClass {
  ///   // #enddocregion outline
  ///   boringMethods() {}
  ///   // #docregion outline
  /// }
  /// // #docregion outline
  /// ```
  ///
  /// The function would be called to render the space between the two continous
  /// regions making up the `outline` snippet.
  ///
  /// The default behavior is to render a single newline.
  final Component Function(
    Excerpt excerpt,
    ContinousRegion last,
    ContinousRegion upcoming,
  )
  writePlaster;

  const UnresolvedRenderingOptions({
    this.mode = const SpanRenderingMode.cssClasses(),
    this.dropIndendation = false,
    this.writePlaster = _defaultPlaster,
  });

  CodeRenderingOptions resolveWith(
    SourceFile file,
    List<HighlightToken>? tokens,
    Excerpt excerpt,
  ) {
    return CodeRenderingOptions(
      file: file,
      tokens: tokens ?? const [],
      excerpt: excerpt,
      mode: mode,
      dropIndendation: dropIndendation,
      writePlaster: writePlaster,
    );
  }

  static Component _defaultPlaster(
    Excerpt excerpt,
    ContinousRegion last,
    ContinousRegion upcoming,
  ) {
    return text('\n');
  }
}

final class CodeRenderingOptions extends UnresolvedRenderingOptions {
  /// The original contents of the snippet file.
  ///
  /// Since excerpts and highlights only store offsets, this is required to
  /// efficiently extract lines or spans of texts.
  final SourceFile file;

  final List<HighlightToken> tokens;

  final Excerpt excerpt;

  CodeRenderingOptions({
    required this.file,
    required this.tokens,
    required this.excerpt,
    super.mode,
    super.dropIndendation,
    super.writePlaster,
  });
}

/// A rendering mode to decide which classes and inline styles to apply for a
/// `<span>` rendering a [HighlightToken].
sealed class SpanRenderingMode {
  /// Render spans with CSS classes (where the class name is the name of the
  /// semantic token type).
  const factory SpanRenderingMode.cssClasses() = _Classes;

  (String?, Styles?) classesAndStylesFor(HighlightToken token);
}

final class _Classes implements SpanRenderingMode {
  const _Classes();

  @override
  (String?, Styles?) classesAndStylesFor(HighlightToken token) {
    final classes = [
      token.type.toJson(),
      if (token.modifiers case final modifiers?)
        for (final modifier in modifiers) modifier.toJson(),
    ].join(' ');

    return (classes, null);
  }
}
