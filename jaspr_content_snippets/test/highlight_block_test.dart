import 'package:jaspr/server.dart';
import 'package:jaspr_content_snippets/src/ui/highlight.dart';
import 'package:test/test.dart';

void main() {
  Jaspr.initializeApp();

  test('dart', () async {
    final component = HighlightBlock(
      source: '''
void main() {
  print('Hello world!');
}
''',
      language: 'dart',
    );

    final rendered = await renderComponent(component, standalone: true);
    expect(rendered.body, '''
<span><span class="keyword void">void</span> <span class="function declaration static">main</span>() {
  <span class="source">print</span>(<span class="string">'Hello world!'</span>);
}</span>
''');
  });

  test('sql', () async {
    final component = HighlightBlock(
      source: '''
query: SELECT * FROM foo;
''',
      language: 'sql',
    );

    final rendered = await renderComponent(component, standalone: true);
    expect(rendered.body, '''
<span><span class="function declaration">query</span>: <span class="keyword">SELECT</span> * <span class="keyword">FROM</span> <span class="class">foo</span>;</span>
''');
  });

  test('yaml', () async {
    final component = HighlightBlock(
      source: '''
foo:
  - bar: true
''',
      language: 'yaml',
    );

    final rendered = await renderComponent(component, standalone: true);
    expect(rendered.body, '''
<span><span class="property">foo</span>:
  - <span class="property">bar</span>: <span class="keyword">true</span></span>
''');
  });

  test('yaml with anchors', () async {
    final component = HighlightBlock(
      source: '''
foo: &common
  - bar: true

bar: *common
''',
      language: 'yaml',
    );

    final rendered = await renderComponent(component, standalone: true);
    expect(rendered.body, '''
<span><span class="property">foo</span>: &amp;common
  - <span class="property">bar</span>: <span class="keyword">true</span>

<span class="property">bar</span>: *common</span>
''');
  });
}
