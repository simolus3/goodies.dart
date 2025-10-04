import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:path/path.dart' show url;

import 'export_canonicalization.dart';

/// An identifier for a top-level (as in, child of a [LibraryElement]) Dart
/// element.
///
/// Since these identifiers are serializable and easy to compute given the
/// [Element], they are used as keys for a generated index storing which element
/// is exported by each public (non-`src/`) library of a package.
final class ElementIdentifier {
  /// The asset id of the source library defining the element.
  final Uri definedSource;

  /// The offset of the element in its source file.
  final int offsetInSource;

  /// For elements defined in the Dart SDK (which don't have a
  /// [Fragment.nameOffset] set on them), their name.
  final String? name;

  ElementIdentifier(this.definedSource, this.offsetInSource, this.name);

  /// Obtains the [ElementIdentifier] for an analyzed [Element].
  static ElementIdentifier? fromElement(Element element) {
    final library = element.library;
    final uri = library?.uri;
    if (library == null || uri == null) {
      return null;
    }

    // Libraries don't necessarily have a name offset, but we still want to be
    // able to link them.
    if (element is LibraryElement) {
      return ElementIdentifier(uri, -1, null);
    }

    final offset = element.firstFragment.nameOffset;
    if (offset == null) {
      final name = element.name;
      if (library.isInSdk && name != null) {
        return ElementIdentifier(uri, 0, element.name);
      }

      return null;
    }

    return ElementIdentifier(uri, offset, null);
  }

  factory ElementIdentifier.fromJson(Map<String, Object?> json) {
    return ElementIdentifier(
      Uri.parse(json['source'] as String),
      json['offset'] as int,
      json['name'] as String?,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'source': definedSource.toString(),
      'offset': offsetInSource,
      'name': name,
    };
  }

  @override
  int get hashCode =>
      Object.hash(ElementIdentifier, definedSource, offsetInSource);

  @override
  bool operator ==(Object other) {
    return other is ElementIdentifier &&
        other.definedSource == definedSource &&
        other.offsetInSource == offsetInSource;
  }
}

/// A public Dart library exported by a package.
///
/// We consider all libraries that aren't defined in `src/` to be public.
final class PublicLibrary {
  /// The asset id of the file defining the library.
  final AssetId id;

  /// All elements in the export namespace of the library.
  final List<ElementIdentifier> exportedElements;

  /// The name `dart doc` uses for this library.
  ///
  /// This depends on a `library` directive, if there is one. Otherwise, it's
  /// derived from the name of the source file.
  ///
  /// This is used to resolve the "primary" library for a given
  /// [ElementIdentifier] if it's exported by multiple libraries.
  final String dartDocName;

  /// The path under which `dart doc` would generate documentation for this
  /// library.
  final String dirName;

  /// Whether the library has a `@deprecated` annotation on it.
  ///
  /// This affects the primary url
  final bool isDeprecated;

  PublicLibrary._(
    this.id,
    this.exportedElements,
    this.dirName,
    this.dartDocName,
    this.isDeprecated,
  );

  factory PublicLibrary.fromJson(Map<String, Object?> json) {
    return PublicLibrary._(
      AssetId.deserialize(json['id'] as List),
      [
        for (final entry in json['exportedElements'] as List)
          ElementIdentifier.fromJson(entry),
      ],
      json['dirName'] as String,
      json['dartDocName'] as String,
      json['isDeprecated'] as bool,
    );
  }

  /// Resolves a [PublicLibrary] from its [AssetId] and resolved
  /// [LibraryElement] by iterating through its
  /// [LibraryElement.exportNamespace].
  factory PublicLibrary(AssetId id, LibraryElement element) {
    final exportedHere = <ElementIdentifier>[];

    for (final export in element.exportNamespace.definedNames2.values) {
      final id = ElementIdentifier.fromElement(export);
      if (id != null) {
        exportedHere.add(id);
      }
    }

    // Also mark the library element itself as exported
    final libraryId = ElementIdentifier.fromElement(element);
    if (libraryId != null) {
      exportedHere.add(libraryId);
    }

    return PublicLibrary._(
      id,
      exportedHere,
      _computeDirName(element, id),
      _computeDartDocName(element, id),
      element.metadata.hasDeprecated,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id.serialize(),
      'exportedElements': [
        for (final element in exportedElements) element.toJson(),
      ],
      'dartDocName': dartDocName,
      'dirName': dirName,
      'isDeprecated': isDeprecated,
    };
  }

  static String _computeDirName(LibraryElement element, AssetId id) {
    if (element.isInSdk) {
      return element.name!.replaceAll('.', '-');
    }

    // Ported over from https://github.com/dart-lang/dartdoc/blob/e1295863b11c54680bf178ec9c2662a33b0e24be/lib/src/model/library.dart#L164
    final name = element.name;
    String nameFromPath;
    if (name == null || name.isEmpty) {
      nameFromPath = url.relative('/${id.path}', from: '/lib');
      if (nameFromPath.endsWith('.dart')) {
        const dartExtensionLength = '.dart'.length;
        nameFromPath = nameFromPath.substring(
          0,
          nameFromPath.length - dartExtensionLength,
        );
      }
    } else {
      nameFromPath = name;
    }

    // Turn `package:foo/bar/baz` into `package-foo_bar_baz`.
    return nameFromPath.replaceAll(':', '-').replaceAll('/', '_');
  }

  static String _computeDartDocName(LibraryElement element, AssetId id) {
    var uri = element.uri;
    if (uri.isScheme('dart')) {
      // There are inconsistencies in library naming + URIs for the Dart
      // SDK libraries; we rationalize them here.
      if (uri.toString().contains('/')) {
        return element.name!.replaceFirst('dart.', 'dart:');
      }
      return uri.toString();
    } else if (element.name != null && element.name!.isNotEmpty) {
      // An empty name indicates that the library is "implicitly named" with the
      // empty string. That is, it either has no `library` directive, or it has
      // a `library` directive with no name.
      return element.name!;
    }

    var baseName = url.basename(id.path);
    if (baseName.endsWith('.dart')) {
      const dartExtensionLength = '.dart'.length;
      return baseName.substring(0, baseName.length - dartExtensionLength);
    }
    return baseName;
  }
}

/// A lazily-loaded index mapping Dart elements to their `dart doc` pages.
class DartIndex {
  static final _resource = Resource(DartIndex.new);

  static Future<DartIndex> of(BuildStep step) => step.fetchResource(_resource);

  final List<String> _loadedPackages = [];
  final Map<ElementIdentifier, List<PublicLibrary>> _knownImports = {};

  Future<PublicLibrary?> publicLibraryForElement(
    Element element,
    BuildStep buildStep,
  ) async {
    // The element itself might be something nested like a getter in a class.
    // Here, we should check if the surrounding class might be exported.
    final possiblyExported = element.thisOrAncestorMatching((element) {
      return element.enclosingElement == null ||
          element.enclosingElement is LibraryElement;
    });

    if (possiblyExported == null) {
      return null;
    }

    return await _importUriForExportedElement(possiblyExported, buildStep);
  }

  Future<PublicLibrary?> _importUriForExportedElement(
    Element element,
    BuildStep buildStep,
  ) async {
    if (element.library?.isInSdk == true) {
      await _loadPackage(r'$sdk', buildStep);
    } else {
      try {
        final id = await buildStep.resolver.assetIdForElement(element);
        await _loadPackage(id.package, buildStep);
      } on UnresolvableAssetException {
        // ignore
        return null;
      }
    }

    final elementId = ElementIdentifier.fromElement(element);
    final candidates = _knownImports[elementId];
    if (elementId == null || candidates == null || candidates.isEmpty) {
      return null;
    }

    if (candidates case [final candidate]) {
      return candidate;
    }

    return Canonicalization(elementId).canonicalLibraryCandidate(candidates);
  }

  Future<void> _loadPackage(String package, BuildStep buildStep) async {
    if (_loadedPackages.contains(package)) {
      return;
    }

    final index = AssetId(package, 'lib/api.json');
    final indexExists = await buildStep.canRead(index);

    if (indexExists) {
      final decl = json.decode(await buildStep.readAsString(index)) as List;

      for (final entry in decl) {
        final library = PublicLibrary.fromJson(entry as Map<String, Object?>);
        for (final exportedElement in library.exportedElements) {
          _knownImports.putIfAbsent(exportedElement, () => []).add(library);
        }
      }

      _loadedPackages.add(package);
    }
  }
}
