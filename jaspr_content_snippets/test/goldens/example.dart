import 'dart:async';

import 'package:build/build.dart';

// #docregion outline
final class ExampleBuilder extends Builder {
  // #enddocregion outline
  // #docregion buildExtensions
  @override
  Map<String, List<String>> get buildExtensions => const {
    '.dart': ['.snippets'],
  };
  // #enddocregion buildExtensions

  // #docregion build
  @override
  FutureOr<void> build(BuildStep buildStep) {
    throw UnimplementedError();
  }

  // #enddocregion build
  // #docregion outline
}

// #enddocregion outline
