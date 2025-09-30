import 'dart:async';
import 'dart:convert';

import 'package:build/build.dart';
import 'package:jaspr/server.dart' hide Builder;
import 'package:jaspr_content_snippets/jaspr_content_snippets.dart';
import 'package:source_span/source_span.dart';

final class GoldenBuilder extends Builder {
  GoldenBuilder([BuilderOptions? options]);

  @override
  Map<String, List<String>> get buildExtensions => {
    '': ['.html'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final id = buildStep.inputId;
    if (id.extension == '.json') {
      // Likely a .snippet.json
      return;
    }

    final snippet = ExtractedExcerpts.fromJson(
      json.decode(
        await buildStep.readAsString(id.addExtension('.snippet.json')),
      ),
    );

    final source = await buildStep.readAsString(id);
    Jaspr.initializeApp();
    final html = await renderComponent(_ShowSnippets(id, source, snippet));

    await buildStep.writeAsString(buildStep.allowedOutputs.single, html.body);
  }
}

final class _ShowSnippets extends AsyncStatelessComponent {
  final AssetId id;
  final String source;
  final ExtractedExcerpts excerpts;

  _ShowSnippets(this.id, this.source, this.excerpts);

  @override
  Future<Component> build(BuildContext context) async {
    final file = SourceFile.fromString(source, url: id.uri);

    return Document(
      head: [
        Style(styles: [css('.keyword').styles(color: Colors.blue)]),
        Style(styles: [css('.type').styles(color: Colors.red)]),
        Style(styles: [css('.class').styles(color: Colors.darkRed)]),
        Style(styles: [css('.property').styles(color: Colors.darkGreen)]),
        Style(styles: [css('.function').styles(color: Colors.yellowGreen)]),
        Style(styles: [css('.method').styles(color: Colors.yellowGreen)]),
        Style(styles: [css('.variable').styles(color: Colors.green)]),
        Style(styles: [css('.parameter').styles(color: Colors.green)]),
        Style(styles: [css('.string').styles(color: Colors.cyan)]),
        Style(styles: [css('.number').styles(color: Colors.darkCyan)]),
        Style(styles: [css('.annotation').styles(color: Colors.lightGreen)]),
        Style(
          styles: [css('.declaration').styles(fontWeight: FontWeight.bold)],
        ),
      ],
      body: fragment([
        for (final excerpt in excerpts.excerpts.values)
          div([
            h2([text(excerpt.name)]),
            code([
              pre([
                ExcerptSpan(
                  options: CodeRenderingOptions(
                    file: file,
                    excerpts: excerpts,
                    name: excerpt.name,
                  ),
                ),
              ]),
            ]),
            hr(),
          ]),
      ]),
      title: id.path,
    );
  }
}
