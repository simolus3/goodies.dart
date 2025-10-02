import 'dart:convert';

import 'package:build/build.dart';
import 'package:dart_style/dart_style.dart';
import 'package:glob/glob.dart';
import 'package:package_config/package_config_types.dart';
import 'package:pub_semver/pub_semver.dart';

import '../highlighted_excerpt.dart';

final class Combiner extends Builder {
  final String outputPath;

  Combiner(this.outputPath);

  @override
  Map<String, List<String>> get buildExtensions => {
    r'$package$': [outputPath],
  };

  @override
  Future<void> build(BuildStep step) async {
    final buffer = StringBuffer('''
final generatedSnippets = {
''');
    var hadExcerpt = false;

    await for (final snippet in step.findAssets(Glob('**/*.snippet.json'))) {
      final excerpt = ExtractedExcerpts.fromJson(
        json.decode(await step.readAsString(snippet)),
      );

      buffer.write("'$snippet': {");

      for (final rendered in excerpt.excerpts) {
        buffer.write("'${rendered.excerpt.name}': r'''${rendered.html}''',");
        hadExcerpt = true;
      }

      buffer.writeln('},');
    }

    buffer.writeln('};');

    if (hadExcerpt) {
      var result = buffer.toString();

      try {
        final config = await step.packageConfig;
        final version = config.packages.singleWhere(
          (e) => e.name == step.inputId.package,
        );

        DartFormatter(
          languageVersion: switch (version.languageVersion) {
            LanguageVersion(:final major, :final minor) => Version(
              major,
              minor,
              0,
            ),
            null => Version(3, 6, 0),
          },
        ).format(result);
      } catch (e, s) {
        log.warning('Could not format source', e, s);
      }

      await step.writeAsString(step.allowedOutputs.single, buffer.toString());
    }
  }
}
