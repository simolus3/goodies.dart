import 'dart:convert';
import 'dart:io';

import 'package:io_uring/io_uring.dart';
import 'package:io_uring/src/io_uring.dart';

Future<void> main() async {
  final ring = await IOUring.initialize() as IOUringImpl;

  await runWithIOUring(() async {
    final file = await File('explore.dart').open();

    await ring.run(ring.close(1, 'stdout'));
  }, ring);
}
