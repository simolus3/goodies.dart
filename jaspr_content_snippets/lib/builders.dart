import 'package:build/build.dart';

import 'src/builders/combiner.dart';
import 'src/builders/excerpts.dart';

export 'src/builders/indexer.dart' show DartIndexBuilder;

Builder excerptsBuilder(BuilderOptions options) {
  final allowWithoutDirectives =
      options.config['process_without_directives'] as bool;
  final dropIndendation = options.config['drop_indentation'] as bool;

  return CodeExcerptBuilder(
    allowWithoutDirectives: allowWithoutDirectives,
    dropIndendation: dropIndendation,
  );
}

Builder combiner(BuilderOptions options) {
  final path = options.config['path'] as String;
  return Combiner(path);
}
