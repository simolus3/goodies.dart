import 'dart:convert';

import 'package:build/build.dart';
import 'package:glob/glob.dart';

import '../highlighted_excerpt.dart';

/// Generates a single Dart file containing string literals for generated
/// highlighting code across all snippets in a package.
///
/// This file is then imported by a custom `jaspr_content` component to render
/// highlights.
final class Combiner extends Builder {
  /// The target path for the generated Dart file.
  final String outputPath;

  Combiner(this.outputPath);

  @override
  Map<String, List<String>> get buildExtensions => {
    r'$package$': [outputPath],
  };

  @override
  Future<void> build(BuildStep step) async {
    final buffer = StringBuffer('''
// dart format off
final generatedSnippets = {
''');
    var hadExcerpt = false;

    await for (final snippet in step.findAssets(Glob('**/*.snippet.json'))) {
      final excerpt = ExtractedExcerpts.fromJson(
        json.decode(await step.readAsString(snippet)),
      );

      buffer.write("'${snippet.path}': {");

      for (final rendered in excerpt.excerpts) {
        buffer.write("'${rendered.excerpt.name}': r'''${rendered.html}''',");
        hadExcerpt = true;
      }

      buffer.writeln('},');
    }

    buffer.writeln('};');

    if (hadExcerpt) {
      await step.writeAsString(step.allowedOutputs.single, buffer.toString());
    }
  }
}
