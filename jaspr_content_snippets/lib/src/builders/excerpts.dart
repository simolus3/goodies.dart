import 'dart:async';
import 'dart:convert';

import 'package:build/build.dart';

import '../excerpts/excerpt.dart';
import '../highlight/dart/highlighter.dart';
import '../highlight/highlighter.dart';
import '../highlight/sql.dart';
import '../highlighted_excerpt.dart';

base class CodeExcerptBuilder implements Builder {
  final bool allowWithoutDirectives;

  CodeExcerptBuilder({required this.allowWithoutDirectives});

  bool shouldEmitFor(AssetId input, Excerpter excerpts) {
    return allowWithoutDirectives || excerpts.containsDirectives;
  }

  Future<Highlighter?> highlighterFor(
    AssetId assetId,
    String content,
    BuildStep buildStep,
  ) async {
    return switch (assetId.extension) {
      '.dart' => DartHighlighter(buildStep),
      '.sql' || '.drift' => SqlHighlighter(buildStep),
      _ => null,
    };
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
      final highlighter = await highlighterFor(assetId, content, buildStep);
      var tokens = await highlighter?.highlight(assetId);
      tokens?.sort(HighlightToken.offsetLengthPrioritySort);
      if (tokens != null) {
        tokens = HighlightToken.splitOverlappingTokens(tokens).toList();
      }

      await buildStep.writeAsString(
        outputAssetId,
        json.encode(
          ExtractedExcerpts(excerpts: excerpts, tokens: tokens).toJson(),
        ),
      );
    }
  }

  @override
  Map<String, List<String>> get buildExtensions => {
    '': ['.snippet.json'],
  };
}
