import 'dart:io';

import 'package:io_uring/io_uring.dart';

const _runs = 100000;

Future<void> main() async {
  final ring = await IOUring.initialize();

  await _testAsync('dart:io');
  await runWithIOUring(() => _testAsync('io_uring'), ring);

  _testSync('dart_io');
  runWithIOUring(() => _testSync('io_uring'), ring);
}

Future<void> _testAsync(String mode) async {
  final sw = Stopwatch()..start();
  final file = File(Platform.script.toFilePath());

  for (var i = 0; i < _runs; i++) {
    await file.stat();
  }

  print('stat (async): time with $mode: ${sw.elapsed}, ');
}

void _testSync(String mode) {
  final sw = Stopwatch()..start();
  final file = File(Platform.script.toFilePath());

  for (var i = 0; i < _runs; i++) {
    file.statSync();
  }

  print('stat (sync): time with $mode: ${sw.elapsed}, ');
}
