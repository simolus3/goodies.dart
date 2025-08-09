@TestOn('vm')
library;

import 'dart:isolate';
import 'dart:math';

import 'package:weblocks/weblocks.dart';
import 'package:test/test.dart';

void main() {
  late String prefix;

  setUp(() {
    const chars = 'abcdefghijklmnopqrstuvwxyz';

    final prefixBuilder = StringBuffer();
    for (var i = 0; i < 8; i++) {
      prefixBuilder.writeCharCode(
        chars.codeUnitAt(_random.nextInt(chars.length)),
      );
    }
    prefix = prefixBuilder.toString();
  });

  test('forgotten to unlock', () async {
    await Isolate.run(() async {
      await lockManager.request(prefix).completion;
    });

    var snapshot = await lockManager.query();
    expect(snapshot.held, isEmpty);
  });
}

final Random _random = Random();
