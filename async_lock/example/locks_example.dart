import 'package:async_lock/async_lock.dart';

void main() async {
  final lockName = 'my-lock';

  final held = await lockManager.request(lockName).completion;
  print('Holds lock: ${held != null}'); // true

  // This will print null
  print(
    'another one? ${await lockManager.request(lockName, ifAvailable: true).completion}',
  );

  final another = lockManager.request(lockName, exclusive: false);
  final snapshot = await lockManager.query();
  print(snapshot); // One pending, one held.

  held!.release();
  final anotherHeld = await another.completion;

  // Because anotherHeld is non-exclusive, we can request more at the same time.
  for (var i = 0; i < 100; i++) {
    final request = lockManager.request(lockName, exclusive: false);
    final granted = await request.completion;
    granted!.release();
  }

  // We can also steal an active lock.
  anotherHeld!.stolen.then((_) => print('lock was stolen'));

  final thief = await lockManager.request(lockName, steal: true).completion;
  thief!.release();

  print(await lockManager.query());
}
