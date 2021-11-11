import 'dart:io';

import 'package:io_uring/io_uring.dart';
import 'package:io_uring/src/io_uring.dart';
import 'package:crypto/crypto.dart';

Future<Digest> digestOf(String path) async {
  return md5.convert(await File(path).readAsBytes());
}

Future<void> main() async {
  final ring = await IOUring.initialize() as IOUringImpl;

  final a =
      await runWithIOUring(() => digestOf('native/dart_io_uring.c'), ring);
  final b = await digestOf('native/dart_io_uring.c');

  print(a);
  print(b);
}
