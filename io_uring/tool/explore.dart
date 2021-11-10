import 'dart:io';

import 'package:io_uring/io_uring.dart';
import 'package:io_uring/src/io_uring.dart';

Future<void> main() async {
  final ring = await IOUring.initialize() as IOUringImpl;

  await runWithIOUring(() async {
    await Socket.connect('127.0.0.1', 8000,
        timeout: const Duration(seconds: 1));
  }, ring);
}
