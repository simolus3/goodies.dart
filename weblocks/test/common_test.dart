import 'package:weblocks/weblocks.dart';
import 'package:test/test.dart';

void main() {
  setUp(() async {
    final current = await lockManager.query();
    expect(current.held, isEmpty);
    expect(current.pending, isEmpty);
  });

  group('basic tests', () {
    test('single lock/unlock cycle', () async {
      final request = lockManager.request('single-lock');
      final held = (await request.completion)!;

      held.release();
    });

    test('snapshot', () async {
      var snapshot = await lockManager.query();
      expect(snapshot.held, isEmpty);
      expect(snapshot.pending, isEmpty);

      final held = await lockManager.request('for-snapshot').completion;
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
      const lockName = 'shared';
      final shared = await Future.wait([
        for (var i = 0; i < 10; i++)
          lockManager.request(lockName, exclusive: false).completion,
      ]);
      expect(shared, everyElement(isNotNull));

      final exclusive = lockManager.request(lockName);
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
      final a = (await lockManager.request('steal').completion)!;
      expect(a.isStolen, isFalse);

      final b = (await lockManager.request('steal', steal: true).completion)!;
      expect(a.isStolen, true);
      b.release();
    });

    test('ifAvailable', () async {
      final a = (await lockManager.request('ifAvailable').completion)!;

      expect(
        await lockManager.request('ifAvailable', ifAvailable: true).completion,
        isNull,
      );
      a.release();
      await pumpEventQueue();

      final b = await lockManager
          .request('ifAvailable', ifAvailable: true)
          .completion;
      expect(b, isNotNull);
      b!.release();
    });

    test('cancel', () async {
      final blocker = await lockManager.request('cancel').completion;

      final request = lockManager.request('cancel');
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
      final request = lockManager.request('cancel-with-steal', steal: true);
      expect(() => request.cancel(), _throws);

      (await request.completion)!.release();
    });

    test('cannot cancel with ifAvailable', () async {
      final request = lockManager.request(
        'cancel-with-if-available',
        ifAvailable: true,
      );
      expect(() => request.cancel(), _throws);
      (await request.completion)!.release();
    });

    test('cannot cancel after lock was granted', () async {
      final request = lockManager.request('cancel-after-granted');
      final held = await request.completion;
      expect(() => request.cancel(), _throws);
      held!.release();
    });
  });

  group('broadcast channel', () {
    test('sends events to other channels', () async {
      final a = lockManager.broadcastChannel('broadcast');
      final b = lockManager.broadcastChannel('broadcast');
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
      final channel = lockManager.broadcastChannel('close-done');
      final didClose = expectLater(channel, emitsDone);

      channel.close();
      await didClose;
    });

    test('does not allow listening after close', () {
      final channel = lockManager.broadcastChannel('listen-after-close')
        ..close();
      expect(() => channel.listen(null), throwsStateError);
    });

    test('does not allow sending after close', () {
      final channel = lockManager.broadcastChannel('send-after-close')..close();
      expect(() => channel.send('foo'), throwsStateError);
    });
  });
}

final _throws = throwsA(anything);
