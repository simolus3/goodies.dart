import 'dart:async';

import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

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

// Stolen from https://github.com/schultek/jaspr/blob/1ef3e7bdf4c18bdbb7f697316bc423e9b82bc2be/packages/jaspr_content/lib/components/_internal/icon.dart#L139-L154
class CopyIcon extends StatelessComponent {
  CopyIcon({this.size});

  final int? size;

  @override
  Component build(BuildContext context) {
    return _Icon(
      size: size,
      children: [
        rect(
          width: "14",
          height: "14",
          x: "8",
          y: "8",
          attributes: {'rx': "2", 'ry': "2"},
          [],
        ),
        path(d: "M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2", []),
      ],
    );
  }
}

class CheckIcon extends StatelessComponent {
  CheckIcon({this.size});

  final int? size;

  @override
  Component build(BuildContext context) {
    return _Icon(
      size: size,
      children: [path(d: 'M20 6 9 17l-5-5', [])],
    );
  }
}

class _Icon extends StatelessComponent {
  _Icon({this.size, required this.children});

  final int? size;
  final List<Component> children;

  @override
  Component build(BuildContext context) {
    return svg(
      width: size?.px,
      height: size?.px,
      viewBox: "0 0 24 24",
      attributes: {
        'fill': 'none',
        'stroke': 'currentColor',
        'stroke-width': '2',
        'stroke-linecap': 'round',
        'stroke-linejoin': 'round',
      },
      children,
    );
  }
}
