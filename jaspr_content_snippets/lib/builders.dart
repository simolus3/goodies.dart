import 'package:build/build.dart';

import 'src/builders/excerpts.dart';

export 'src/builders/indexer.dart' show DartIndexBuilder;

Builder excerptsBuilder(BuilderOptions options) {
  final allowWithoutDirectives =
      options.config['process_without_directives'] as bool;

  return CodeExcerptBuilder(allowWithoutDirectives: allowWithoutDirectives);
}
