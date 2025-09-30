import 'dart:collection';
import 'dart:math' as math;

import 'package:build/build.dart';

import 'token_type.dart';

abstract interface class Highlighter {
  Future<List<HighlightToken>> highlight(AssetId id);
}

final class HighlightToken {
  final int offset;
  final int length;
  final SemanticTokenTypes type;
  final Set<SemanticTokenModifiers>? modifiers;

  Uri? viewableDefinition;
  Uri? documentationUri;

  int get endOffset => offset + length;

  HighlightToken({
    required this.offset,
    required this.length,
    required this.type,
    this.modifiers,
    this.viewableDefinition,
    this.documentationUri,
  });

  factory HighlightToken.fromJson(Map<String, Object?> json) {
    return HighlightToken(
      offset: json['o'] as int,
      length: json['l'] as int,
      type: SemanticTokenTypes.fromJson(json['t'] as String),
      modifiers: switch (json['m']) {
        null => null,
        final raw as List => {
          for (final modifier in raw)
            SemanticTokenModifiers.fromJson(modifier as String),
        },
      },
      viewableDefinition: switch (json['s']) {
        null => null,
        final s as String => Uri.parse(s),
      },
      documentationUri: switch (json['d']) {
        null => null,
        final d as String => Uri.parse(d),
      },
    );
  }

  Map<String, Object?> toJson() {
    return {
      'o': offset,
      'l': length,
      't': type.toJson(),
      'm': modifiers?.map((e) => e.toJson()).toList(),
      's': viewableDefinition?.toString(),
      'd': documentationUri?.toString(),
    };
  }

  /// Sorter for semantic tokens that ensures tokens are sorted in offset order
  /// then longest first, then by priority, and finally by name. This ensures
  /// the order is always stable.
  static int offsetLengthPrioritySort(HighlightToken t1, HighlightToken t2) {
    var priorities = {
      // Ensure boolean comes above keyword.
      CustomSemanticTokenTypes.boolean: 1,
    };

    // First sort by offset.
    if (t1.offset != t2.offset) {
      return t1.offset.compareTo(t2.offset);
    }

    // Then length (so longest are first).
    if (t1.length != t2.length) {
      return -t1.length.compareTo(t2.length);
    }

    // Next sort by priority (if different).
    var priority1 = priorities[t1.type] ?? 0;
    var priority2 = priorities[t2.type] ?? 0;
    if (priority1 != priority2) {
      return priority1.compareTo(priority2);
    }

    // The code below ensures consistent results for users, but ideally we don't
    // get here, so use an assert to fail any tests/debug builds if we failed
    // to sort based on the offset/length/priorities above.
    assert(
      false,
      'Failed to resolve semantic token ordering by offset/length/priority:\n'
      '${t1.offset}:${t1.length} ($priority1) - ${t1.type} / ${t1.modifiers?.join(', ')}\n'
      '${t2.offset}:${t2.length} ($priority2) - ${t2.type} / ${t2.modifiers?.join(', ')}\n'
      'Perhaps an explicit priority needs to be added?',
    );

    // If the tokens had the same offset and length, sort by name. This
    // is completely arbitrary but it's only important that it is consistent
    // between tokens and the sort is stable.
    return t1.type.toString().compareTo(t2.type.toString());
  }

  /// Splits overlapping/nested tokens into discrete ranges for the "top-most"
  /// token.
  ///
  /// Tokens must be pre-sorted by offset, with tokens having the same offset
  /// sorted with the longest first.
  static Iterable<HighlightToken> splitOverlappingTokens(
    Iterable<HighlightToken> sortedTokens,
  ) sync* {
    if (sortedTokens.isEmpty) {
      return;
    }

    var stack = ListQueue<HighlightToken>();

    /// Yields tokens for anything on the stack from between [fromOffset]
    /// and [toOffset].
    Iterable<HighlightToken> processStack(int fromOffset, int toOffset) sync* {
      // Process each item on the stack to figure out if we need to send
      // a token for it, and pop it off the stack if we've passed the end of it.
      while (stack.isNotEmpty) {
        var last = stack.last;
        var lastEnd = last.offset + last.length;
        var end = math.min(lastEnd, toOffset);
        var length = end - fromOffset;
        if (length > 0) {
          yield HighlightToken(
            offset: fromOffset,
            length: length,
            type: last.type,
            modifiers: last.modifiers,
            documentationUri: last.documentationUri,
            viewableDefinition: last.viewableDefinition,
          );
          fromOffset = end;
        }

        // If this token is completely done with, remove it and continue
        // through the stack. Otherwise, if this token remains then we're done
        // for now.
        if (lastEnd <= toOffset) {
          stack.removeLast();
        } else {
          return;
        }
      }
    }

    var lastPos = sortedTokens.first.offset;
    for (var current in sortedTokens) {
      // Before processing each token, process the stack as there may be tokens
      // on it that need filling in the gap up until this point.
      yield* processStack(lastPos, current.offset);

      // Add this token to the stack but don't process it, it will be done by
      // the next iteration processing the stack since we don't know where this
      // one should end until we see the start of the next one.
      stack.addLast(current);
      lastPos = current.offset;
    }

    // Process any remaining stack after the last region.
    if (stack.isNotEmpty) {
      yield* processStack(lastPos, stack.first.offset + stack.first.length);
    }
  }
}
