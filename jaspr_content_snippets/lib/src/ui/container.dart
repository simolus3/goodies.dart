import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_content_snippets/internal/client.dart';

final class CodeSnippetContainer extends StatelessComponent {
  final Component child;

  CodeSnippetContainer({super.key, required this.child});

  @override
  Component build(BuildContext context) {
    final codeblock = pre([
      code([child]),
    ]);

    return div(classes: 'code-block', [CodeBlockCopyButton(), codeblock]);
  }
}
