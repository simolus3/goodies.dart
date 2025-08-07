import 'dart:isolate';
import 'dart:math';

import 'package:locks/locks.dart';
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

  group('basic', () {
    test('single lock/unlock cycle', () async {
      final request = lockManager.request(prefix);
      final held = (await request.completion)!;

      held.release();
    });

    test('snapshot', () async {
      var snapshot = await lockManager.query();
      expect(snapshot.held, isEmpty);
      expect(snapshot.pending, isEmpty);

      final held = await lockManager.request(prefix).completion;
      snapshot = await lockManager.query();
      expect(snapshot.held, hasLength(1));
      expect(snapshot.pending, isEmpty);
      held!.release();
    });

    test('forgotten to unlock', () async {
      await Isolate.run(() async {
        await lockManager.request(prefix).completion;
      });

      var snapshot = await lockManager.query();
      expect(snapshot.held, isEmpty);
    });
  });
}

final Random _random = Random();
