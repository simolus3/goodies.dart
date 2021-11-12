import 'dart:io';

import 'package:io_uring/io_uring.dart';
import 'package:io_uring/src/io_uring.dart';

Future<void> main() async {
  final ring = await IOUring.initialize() as IOUringImpl;

  await runWithIOUring(() async {
    final socket = await ServerSocket.bind(
        InternetAddress('/tmp/test', type: InternetAddressType.unix), 0);
    await socket.first;
  }, ring);
}
