// https://github.com/dart-lang/sdk/issues/44006
import 'dart:io';
import 'dart:typed_data';

import 'package:io_uring/io_uring.dart';

const _length = 16 * 1024 * 1024 * 1024; // 16 GiB

Future<void> main() async {
  final ring = await IOUring.initialize();

  await _testAsync('dart:io');
  await runWithIOUring(() => _testAsync('io_uring'), ring);

  _testSync('dart_io');
  runWithIOUring(() => _testSync('io_uring'), ring);
}

Future<void> _testAsync(String mode) async {
  final sw = Stopwatch()..start();
  final file = File('/dev/zero');
  final fileStream = file.openRead(null, _length);

  var eventCount = 0;
  var totalSize = 0;

  await for (final chunk in fileStream) {
    eventCount++;
    totalSize += chunk.length;
  }
  print('openRead: time with $mode: ${sw.elapsed}, '
      'avg. size: ${totalSize / eventCount}');
}

void _testSync(String mode) {
  final sw = Stopwatch()..start();
  final file = File('/dev/zero').openSync(mode: FileMode.read);
  var read = 0;
  final buffer = Uint8List(65536);

  while (read < _length) {
    file.readIntoSync(buffer);
    read += buffer.length;
  }

  file.closeSync();
  print('openSync/readIntoSync: time with $mode: ${sw.elapsed}');
}
