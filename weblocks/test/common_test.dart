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

  group('basic tests', () {
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

      await pumpEventQueue();
      snapshot = await lockManager.query();
      expect(snapshot.held, isEmpty);
      expect(snapshot.pending, isEmpty);
    });

    test('shared', () async {
      final shared = await Future.wait([
        for (var i = 0; i < 10; i++)
          lockManager.request(prefix, exclusive: false).completion,
      ]);
      expect(shared, everyElement(isNotNull));

      final exclusive = lockManager.request(prefix);
      var snapshot = await lockManager.query();
      expect(snapshot.held, hasLength(10));
      expect(snapshot.pending, hasLength(1));

      for (final held in shared) {
        held!.release();
      }

      final heldExclusive = await exclusive.completion;
      expect(heldExclusive, isNotNull);
      heldExclusive!.release();
    });

    test('steal', () async {
      final a = (await lockManager.request(prefix).completion)!;
      expect(a.isStolen, isFalse);

      final b = (await lockManager.request(prefix, steal: true).completion)!;
      expect(a.isStolen, true);
      b.release();
    });

    test('ifAvailable', () async {
      final a = (await lockManager.request(prefix).completion)!;

      expect(
        await lockManager.request(prefix, ifAvailable: true).completion,
        isNull,
      );
      a.release();
      await pumpEventQueue();

      final b = await lockManager.request(prefix, ifAvailable: true).completion;
      expect(b, isNotNull);
      b!.release();
    });

    test('cancel', () async {
      final blocker = await lockManager.request(prefix).completion;

      final request = lockManager.request(prefix);
      request.cancel();
      expect(request.completion, throwsA(isA<LockRequestCancelled>()));

      blocker!.release();
    });
  });

  group('request validation', () {
    test('cannot request locks starting with hyphen', () async {
      expect(() => lockManager.request('-invalid').completion, _throws);
    });

    test('cannot combine steal and ifAvailable', () async {
      expect(
        () => lockManager
            .request('invalid', steal: true, ifAvailable: true)
            .completion,
        _throws,
      );
    });

    test('cannot steal with shared', () async {
      expect(
        () => lockManager
            .request('valid', steal: true, exclusive: false)
            .completion,
        _throws,
      );
    });

    test('cannot cancel with steal', () async {
      final request = lockManager.request(prefix, steal: true);
      expect(() => request.cancel(), _throws);
    });

    test('cannot cancel with ifAvailable', () async {
      final request = lockManager.request(prefix, ifAvailable: true);
      expect(() => request.cancel(), _throws);
    });

    test('cannot cancel after lock was granted', () async {
      final request = lockManager.request(prefix);
      final held = await request.completion;
      expect(() => request.cancel(), _throws);
      held!.release();
    });
  });

  group('broadcast channel', () {
    test('sends events to other channels', () async {
      final a = lockManager.broadcastChannel(prefix);
      final b = lockManager.broadcastChannel(prefix);
      a.send('before-listen');
      await pumpEventQueue();

      final allMessagesOnB = b.toList();
      final allMessagesOnA = a.toList();

      a.send('a');
      b.send('b');

      await pumpEventQueue();
      a.close();
      b.close();

      expect(await allMessagesOnA, ['b']);
      expect(await allMessagesOnB, ['a']);
    });

    test('closing emits done event', () async {
      final channel = lockManager.broadcastChannel(prefix);
      final didClose = expectLater(channel, emitsDone);

      channel.close();
      await didClose;
    });

    test('does not allow listening after close', () {
      final channel = lockManager.broadcastChannel(prefix)..close();
      expect(() => channel.listen(null), throwsStateError);
    });

    test('does not allow sending after close', () {
      final channel = lockManager.broadcastChannel(prefix)..close();
      expect(() => channel.send('foo'), throwsStateError);
    });
  });
}

final Random _random = Random();
final _throws = throwsA(anything);
