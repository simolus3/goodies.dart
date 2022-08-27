import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../io_uring.dart';
import '../linux/file.dart';
import 'file.dart';

class RingBasedStdin extends Stream<List<int>> implements Stdin {
  final Stdin _nativeSdin;

  final ReadFromFdStream _stream;

  RingBasedStdin(this._nativeSdin, IOUringImpl ring)
      : _stream = ReadFromFdStream(ring, STDIN_FILENO, path: 'stdin');

  @override
  bool get echoMode => _nativeSdin.echoMode;

  @override
  set echoMode(bool value) => _nativeSdin.echoMode = value;

  @override
  bool get lineMode => _nativeSdin.lineMode;

  @override
  set lineMode(bool value) => _nativeSdin.lineMode = value;

  @override
  bool get hasTerminal => _nativeSdin.hasTerminal;

  @override
  bool get supportsAnsiEscapes => _nativeSdin.supportsAnsiEscapes;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return _stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  int readByteSync() => _stream.readByteSync();

  @override
  String? readLineSync(
      {Encoding encoding = systemEncoding, bool retainNewlines = false}) {
    // We're on a decent platform, so a linebreak is just \n
    const lf = 10;
    final List<int> line = <int>[];

    while (true) {
      final byte = readByteSync();
      if (byte < 0) break; // stdin closed

      if (byte == lf) {
        if (retainNewlines) line.add(byte);
        break;
      }

      line.add(byte);
    }

    return encoding.decode(line);
  }
}
