import 'dart:async';
import 'dart:convert';

import 'package:build/build.dart';
import 'package:glob/glob.dart';

import '../dartdoc/dart_index.dart';

/// Creates an index of all top-level public members exported by a package.
///
/// This can later be used by the highlighter to resolve documentation URIs,
/// which requires knowing the right public import to use for an `src/` path.
class DartIndexBuilder implements Builder {
  final List<String> packagesToIndex;

  DartIndexBuilder.custom(this.packagesToIndex);

  factory DartIndexBuilder(BuilderOptions options) {
    final packages = options.config['packages'] as List?;

    return DartIndexBuilder.custom(packages?.cast<String>() ?? const []);
  }

  @override
  Future<void> build(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    if (!packagesToIndex.contains(buildStep.inputId.package)) return;

    final output = buildStep.allowedOutputs.single;
    final publicLibraries = <PublicLibrary>[];

    if (package == r'$sdk') {
      await for (final library in buildStep.resolver.libraries) {
        if (library.name case final name?) {
          publicLibraries.add(PublicLibrary(AssetId(package, name), library));
        }
      }
    } else {
      final src = Glob('lib/src/**');

      await for (final input in buildStep.findAssets(Glob('lib/**.dart'))) {
        if (src.matches(input.path)) continue;

        final library = await buildStep.resolver.libraryFor(input);
        publicLibraries.add(PublicLibrary(input, library));
      }
    }

    await buildStep.writeAsString(output, json.encode(publicLibraries));
  }

  @override
  Map<String, List<String>> get buildExtensions => const {
    r'$package$': ['lib/api.json'],
  };
}
