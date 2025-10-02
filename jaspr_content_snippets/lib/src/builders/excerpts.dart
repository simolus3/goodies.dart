import 'dart:async';
import 'dart:convert';

import 'package:build/build.dart';
import 'package:jaspr/server.dart' hide Builder;
import 'package:source_span/source_span.dart';

import '../excerpts/excerpt.dart';
import '../highlight/dart/highlighter.dart';
import '../highlight/highlighter.dart';
import '../highlight/sql.dart';
import '../highlighted_excerpt.dart';
import '../ui/options.dart';
import '../ui/span.dart';

base class CodeExcerptBuilder implements Builder {
  final bool allowWithoutDirectives;

  CodeExcerptBuilder({required this.allowWithoutDirectives});

  bool shouldEmitFor(AssetId input, Excerpter excerpts) {
    return allowWithoutDirectives || excerpts.containsDirectives;
  }

  Future<Highlighter?> highlighterFor(BuildStep buildStep) async {
    return switch (buildStep.inputId.extension) {
      '.dart' => DartHighlighter(buildStep),
      '.sql' || '.drift' => SqlHighlighter(buildStep),
      _ => null,
    };
  }

  Future<UnresolvedRenderingOptions> renderingOptionsFor(
    BuildStep buildStep,
  ) async {
    return const UnresolvedRenderingOptions();
  }

  @override
  Future<void> build(BuildStep buildStep) async {
    final assetId = buildStep.inputId;
    if (assetId.package.startsWith(r'$') || assetId.path.endsWith(r'$')) return;

    final content = await buildStep.readAsString(assetId);
    final outputAssetId = buildStep.allowedOutputs.single;

    final excerpter = Excerpter(assetId.path, content)..weave();
    final excerpts = excerpter.excerpts;

    if (shouldEmitFor(assetId, excerpter)) {
      final highlighter = await highlighterFor(buildStep);
      var tokens = await highlighter?.highlight(assetId);
      tokens?.sort(HighlightToken.offsetLengthPrioritySort);
      if (tokens != null) {
        tokens = HighlightToken.splitOverlappingTokens(tokens).toList();
      }

      final baseOptions = await renderingOptionsFor(buildStep);
      final file = SourceFile.fromString(content, url: assetId.uri);
      final rendered = <RenderedExcerpt>[];
      for (final excerpt in excerpts.values) {
        Jaspr.initializeApp();
        final html = await renderComponent(
          standalone: true,
          ExcerptSpan(options: baseOptions.resolveWith(file, tokens, excerpt)),
        );

        rendered.add(RenderedExcerpt(excerpt: excerpt, html: html.body));
      }

      final extracted = ExtractedExcerpts(excerpts: rendered, tokens: tokens);

      await buildStep.writeAsString(
        outputAssetId,
        json.encode(extracted.toJson()),
      );
    }
  }

  @override
  Map<String, List<String>> get buildExtensions => {
    '': ['.snippet.json'],
  };
}
