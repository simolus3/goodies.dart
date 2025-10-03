/// Client code this package contributes to jaspr websites.
///
/// This is a public library because it gets auto-imported by jaspr client
/// component code, but it should not be imported manually. Having it in a
/// public library works better with `build_modules` inferring transitive
/// imports.
library;

import 'dart:async';

import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

import '../src/ui/icons.dart';

// Stolen from https://github.com/schultek/jaspr/blob/1ef3e7bdf4c18bdbb7f697316bc423e9b82bc2be/packages/jaspr_content/lib/components/_internal/code_block_copy_button.dart#L9
@client
class CodeBlockCopyButton extends StatefulComponent {
  const CodeBlockCopyButton({super.key});

  @override
  State<CodeBlockCopyButton> createState() => _CodeBlockCopyButtonState();
}

class _CodeBlockCopyButtonState extends State<CodeBlockCopyButton> {
  bool copied = false;

  @override
  Component build(BuildContext context) {
    return button(
      events: {
        'click': (event) {
          final target = event.currentTarget as web.Element;
          final content = target.parentElement
              ?.querySelector('pre code')
              ?.textContent;
          if (content == null) {
            return;
          }
          web.window.navigator.clipboard.writeText(content);
          setState(() {
            copied = true;
          });
          Timer(const Duration(seconds: 2), () {
            setState(() {
              copied = false;
            });
          });
        },
      },
      [copied ? CheckIcon(size: 18) : CopyIcon(size: 18)],
    );
  }
}
