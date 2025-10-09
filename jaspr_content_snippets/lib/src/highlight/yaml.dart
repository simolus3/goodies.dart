// ignore_for_file: unused_import

import 'package:yaml/yaml.dart';

import '../../jaspr_content_snippets.dart';

final class YamlHighlighter implements SyntaxOnlyHighlighter {
  @override
  List<HighlightToken> highlightWithoutContext(String source) {
    final parsed = loadYamlNode(source);
    final visitor = _YamlVisitor()..process(parsed);

    return visitor.tokens;
  }
}

final class _YamlVisitor {
  /// Keep track of all visited nodes to avoid highlighting regions multiple
  /// times if they're reused as anchors.
  final Set<YamlNode> _visited = {};
  final List<HighlightToken> tokens = [];

  void processMap(YamlMap map) {
    map.nodes.forEach((key, value) {
      highlight(key as YamlNode, SemanticTokenTypes.property);
      process(value);
    });
  }

  void processList(YamlList list) {
    for (final entry in list.nodes) {
      process(entry);
    }
  }

  void processScalar(YamlScalar scalar) {
    highlight(scalar, switch (scalar.value) {
      null || bool() => SemanticTokenTypes.keyword,
      num() => SemanticTokenTypes.number,
      _ => SemanticTokenTypes.string,
    });
  }

  void highlight(YamlNode scalar, SemanticTokenTypes types) {
    tokens.add(
      HighlightToken(
        offset: scalar.span.start.offset,
        length: scalar.span.length,
        type: types,
      ),
    );
  }

  void process(YamlNode node) {
    if (!_visited.add(node)) {
      return;
    }

    switch (node) {
      case YamlMap():
        processMap(node);
      case YamlList():
        processList(node);
      case YamlScalar():
        processScalar(node);
    }
  }
}
