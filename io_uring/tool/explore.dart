import 'dart:convert';
import 'dart:io';

import 'package:io_uring/io_uring.dart';
import 'package:io_uring/src/io_uring.dart';

Future<void> main() async {
  final socket = await Socket.connect('simonbinder.eu', 80);

  socket.listen((data) {
    print('received ${data.length} bytes');
  });

  print('connected');
}
