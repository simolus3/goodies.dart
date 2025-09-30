// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
// Adopted from https://github.com/dart-lang/dartdoc/blob/e1295863b11c54680bf178ec9c2662a33b0e24be/lib/src/model/canonicalization.dart#L11

import 'package:build/build.dart';

import 'dart_index.dart';

/// Canonicalization support in Dartdoc.
///
/// This provides heuristic scoring to determine which library a human likely
/// considers this element to be primarily 'from', and therefore, canonical.
/// Still warn if the heuristic isn't very confident.
final class Canonicalization {
  final ElementIdentifier _element;

  Canonicalization(this._element);

  /// Calculates a candidate for the canonical library of [_element], among [libraries].
  PublicLibrary canonicalLibraryCandidate(Iterable<PublicLibrary> libraries) {
    var definedSource = _element.definedSource;
    var locationPieces = const <String>{};
    if (definedSource.isScheme('package') || definedSource.isScheme('asset')) {
      var asset = AssetId.resolve(definedSource);
      locationPieces = {asset.package, ...asset.pathSegments};
    }

    var scoredCandidates =
        libraries
            .map((library) => _scoreElementWithLibrary(library, locationPieces))
            .toList(growable: false)
          ..sort();

    final librariesByScore = scoredCandidates.map((s) => s.library).toList();
    final canonicalLibrary = librariesByScore.last;

    return canonicalLibrary;
  }

  static _ScoredCandidate _scoreElementWithLibrary(
    PublicLibrary library,
    Set<String> elementLocationPieces,
  ) {
    var scoredCandidate = _ScoredCandidate(library);

    // Penalty for deprecated libraries.
    if (library.isDeprecated) {
      scoredCandidate._alterScore(-1.0, _Reason.deprecated);
    }

    var libraryNamePieces = {
      ...library.dartDocName.split('.').where((s) => s.isNotEmpty),
    };

    // Give a big boost if the library has the package name embedded in it.
    if (libraryNamePieces.contains(library.id.package)) {
      scoredCandidate._alterScore(1.0, _Reason.packageName);
    }

    // Give a tiny boost for libraries with long names, assuming they're
    // more specific (and therefore more likely to be the owner of this symbol).
    scoredCandidate._alterScore(
      .01 * libraryNamePieces.length,
      _Reason.longName,
    );

    // If we don't know the location of this element (which shouldn't be
    // possible), return our best guess.
    assert(elementLocationPieces.isNotEmpty);
    if (elementLocationPieces.isEmpty) return scoredCandidate;

    // The more pieces we have of the location in our library name, the more we
    // should boost our score.
    scoredCandidate._alterScore(
      libraryNamePieces.intersection(elementLocationPieces).length.toDouble() /
          elementLocationPieces.length.toDouble(),
      _Reason.sharedNamePart,
    );

    // If pieces of location at least start with elements of our library name,
    // boost the score a little bit.
    var scoreBoost = 0.0;
    for (var piece in elementLocationPieces.expand((item) => item.split('_'))) {
      for (var namePiece in libraryNamePieces) {
        if (piece.startsWith(namePiece)) {
          scoreBoost += 0.001;
        }
      }
    }
    scoredCandidate._alterScore(scoreBoost, _Reason.locationPartStart);
    return scoredCandidate;
  }
}

/// This class represents the score for a particular element; how likely
/// it is that this is the canonical element.
class _ScoredCandidate implements Comparable<_ScoredCandidate> {
  final List<(_Reason, double)> _reasons = [];

  final PublicLibrary library;

  /// The score accumulated so far.  Higher means it is more likely that this
  /// is the intended canonical Library.
  double score = 0.0;

  _ScoredCandidate(this.library);

  void _alterScore(double scoreDelta, _Reason reason) {
    score += scoreDelta;
    if (scoreDelta != 0) {
      _reasons.add((reason, scoreDelta));
    }
  }

  @override
  int compareTo(_ScoredCandidate other) => score.compareTo(other.score);

  @override
  String toString() {
    var reasonText = _reasons.map((r) {
      var (reason, scoreDelta) = r;
      var scoreDeltaPrefix = scoreDelta >= 0 ? '+' : '';
      return '$reason ($scoreDeltaPrefix${scoreDelta.toStringAsPrecision(4)})';
    });
    return '${library.dartDocName}: ${score.toStringAsPrecision(4)} - $reasonText';
  }
}

/// A reason that a candidate's score is changed.
enum _Reason {
  deprecated('is deprecated'),
  packageName('embeds package name'),
  longName('name is long'),
  sharedNamePart('element location shares parts with name'),
  locationPartStart('element location parts start with parts of name');

  final String text;

  const _Reason(this.text);
}
