import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:build/build.dart';

import '../highlighter.dart';
import 'computer_highlights.dart';

/// A highlighter for Dart sources, using highlighting code extracted from the
/// analysis server running against build resolvers.
final class DartHighlighter implements Highlighter {
  final BuildStep buildStep;

  DartHighlighter(this.buildStep);

  @override
  Future<List<HighlightToken>> highlight(AssetId id) async {
    final library = await buildStep.resolver.libraryFor(
      id,
      allowSyntaxErrors: true,
    );
    final path = library.session.uriConverter.uriToPath(library.uri)!;
    final resolveResult = switch (await library.session.getResolvedUnit(path)) {
      final ResolvedUnitResult result => result,
      final other => throw StateError('Could not resolve $path: $other'),
    };

    final computer = DartUnitHighlightsComputer(resolveResult.unit);
    final semanticTokens = computer.computeSemanticTokens();
    semanticTokens.sort(HighlightToken.offsetLengthPrioritySort);

    // Add dartdoc references to found tokens
    await computer.referencedElements.resolveAgainstSortedTokens(
      semanticTokens,
      buildStep,
    );

    return semanticTokens;
  }
}

final class SyntacticDartHighlighter implements SyntaxOnlyHighlighter {
  @override
  List<HighlightToken> highlightWithoutContext(String source) {
    final result = parseString(content: source, throwIfDiagnostics: false);

    final computer = DartUnitHighlightsComputer(result.unit);
    final semanticTokens = computer.computeSemanticTokens();

    return semanticTokens;
  }
}
