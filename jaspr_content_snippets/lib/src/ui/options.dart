import 'package:jaspr/server.dart';
import 'package:source_span/source_span.dart';
import 'package:syntax_highlight_lite/syntax_highlight_lite.dart' hide Color;

import '../excerpts/excerpt.dart';
import '../highlight/highlighter.dart';
import '../highlight/token_type.dart';

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

  /// Render inline styles derived from the [HighlighterTheme].
  const factory SpanRenderingMode.highlighter(HighlighterTheme theme) =
      _HighlighterTheme;

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

final class _HighlighterTheme implements SpanRenderingMode {
  final HighlighterTheme _theme;

  const _HighlighterTheme(this._theme);

  @override
  (String?, Styles?) classesAndStylesFor(HighlightToken token) {
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
