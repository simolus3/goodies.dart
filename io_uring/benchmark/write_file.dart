import 'dart:io';
import 'dart:typed_data';

import 'package:io_uring/io_uring.dart';

const _chunkSize = 1024 * 512; // 0.5 MiB
const _totalChunks = 1024 * 10; // 5 GiB

final Uint8List _chunk = Uint8List(_chunkSize);

Future<void> main() async {
  final ring = await IOUring.initialize();

  await _testAsync('dart:io');
  await runWithIOUring(() => _testAsync('io_uring'), ring);

  _testSync('dart_io');
  runWithIOUring(() => _testSync('io_uring'), ring);
}

Future<void> _testAsync(String mode) async {
  final sw = Stopwatch()..start();
  final file = File('/dev/null');
  final fileStream = file.openWrite();

  for (var i = 0; i < _totalChunks; i++) {
    fileStream.add(_chunk);
  }

  await fileStream.close();
  print('openWrite: time with $mode: ${sw.elapsed}');
}

void _testSync(String mode) {
  final sw = Stopwatch()..start();
  final file = File('/dev/null').openSync(mode: FileMode.write);

  for (var i = 0; i < _totalChunks; i++) {
    file.writeFromSync(_chunk);
  }

  file.closeSync();
  print('openSync/writeFromSync: time with $mode: ${sw.elapsed}');
}
