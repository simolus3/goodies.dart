import 'dart:io';
import 'dart:typed_data';

import 'package:chacha20/chacha20.dart';
import 'package:convert/convert.dart';

Future<void> main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('Usage: dart run example/chacha20.dart <hex-key> <hex-iv>');
    stderr.flush();
    exit(1);
  }

  final key = Uint8List.fromList(hex.decode(args[0]));
  final iv = Uint8List.fromList(hex.decode(args[1]));

  final chacha20 = ChaCha20(key, iv);
  return stdin.transform(chacha20.encoder).pipe(stdout);
}
