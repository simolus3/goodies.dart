import 'package:jaspr/server.dart';
import 'package:jaspr_content_snippets/jaspr_content_snippets.dart';
import 'package:source_span/source_span.dart';
import 'package:test/test.dart';

void main() {
  Jaspr.initializeApp();

  test('can render excerpt with indent', () async {
    final span = ExcerptSpan(
      options: CodeRenderingOptions(
        file: SourceFile.fromString('''
1
  2
  3
4
'''),
        tokens: const [],
        excerpt: Excerpt('a', [ContinousRegion(1, 3, indentation: '  ')]),
        dropIndendation: true,
      ),
    );

    final result = await renderComponent(span, standalone: true);
    expect(result.body, '''
<span>2
3</span>
''');
  });
}
