import 'package:analyzer/dart/analysis/results.dart';
import 'package:build/build.dart';

import '../highlighter.dart';
import 'computer_highlights.dart';

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
