import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';

import '../../dartdoc/dart_index.dart';
import '../../dartdoc/uris.dart';
import '../highlighter.dart';

/// For identifier tokens fond by the highlights computer, asynchronously
/// resolves suitable `dart doc` links.
final class ElementReferences {
  final _pending = <_PendingElementReference>[];

  void trackElement(SyntacticEntity token, Element element) {
    _pending.add(_PendingElementReference(token.offset, token.length, element));
  }

  Future<void> resolveAgainstSortedTokens(
    List<HighlightToken> tokens,
    BuildStep buildStep,
  ) async {
    final index = await DartIndex.of(buildStep);

    for (final reference in _findReferences(tokens)) {
      final import = await index.publicLibraryForElement(
        reference.element,
        buildStep,
      );

      if (import != null) {
        reference.token.documentationUri = _dartDocUri(
          import,
          reference.element,
        );
      }
    }
  }

  Iterable<_MatchedReference> _findReferences(
    List<HighlightToken> tokens,
  ) sync* {
    // Sort references with the same comparator as tokens.
    _pending.sort((a, b) {
      // First sort by offset.
      if (a.offset != b.offset) {
        return a.offset.compareTo(b.offset);
      }

      // Then length (so longest are first).
      if (a.length != b.length) {
        return -a.length.compareTo(b.length);
      }

      // Apart from these we don't need a stable sort here.
      return 0;
    });

    var iterator = _pending.iterator;
    if (!iterator.moveNext()) {
      return;
    }

    for (final token in tokens) {
      // Find an element reference matching this token.
      while (iterator.current.offset < token.offset) {
        if (!iterator.moveNext()) {
          return;
        }
      }

      if (iterator.current.offset == token.offset &&
          iterator.current.length == token.length) {
        yield _MatchedReference(iterator.current.element, token);
      }
    }
  }

  Uri _dartDocUri(PublicLibrary library, Element element) {
    // TODO: Support overriding dartdoc base URIs?
    final base = defaultDocumentationUri(library.id.package);

    return documentationForElement(element, library.dirName, base);
  }
}

final class _PendingElementReference {
  final int offset;
  final int length;
  final Element element;

  _PendingElementReference(this.offset, this.length, this.element);
}

final class _MatchedReference {
  final Element element;
  final HighlightToken token;

  _MatchedReference(this.element, this.token);
}
