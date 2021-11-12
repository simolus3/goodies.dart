import 'package:io_uring/io_uring.dart';
import 'package:io_uring/src/io_uring.dart';

const _iterations = 1000000;

Future<void> main() async {
  final ring = await IOUring.initialize() as IOUringImpl;

  _testSync(ring);
  await _testAsync(ring);
}

void _testSync(IOUringImpl ring) {
  final sw = Stopwatch()..start();

  for (var i = 0; i < _iterations; i++) {
    ring.runSync(ring.nop());
  }

  print('Sync: took ${sw.elapsed} for $_iterations runs');
}

Future<void> _testAsync(IOUringImpl ring) async {
  final sw = Stopwatch()..start();

  for (var i = 0; i < _iterations; i++) {
    await ring.run(ring.nop());
  }

  print('Async: took ${sw.elapsed} for $_iterations runs');
}
