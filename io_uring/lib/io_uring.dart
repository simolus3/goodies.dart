import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'src/io_uring.dart';
import 'src/ring/binding.dart';
import 'src/ring/polling_queue.dart';

export 'src/dart_io/overrides.dart';

abstract class IOUring {
  IOUring._();

  Future<void> dispose();

  static Future<IOUring> initialize(
      {DynamicLibrary? helper, Allocator alloc = malloc}) async {
    DynamicLibrary? resolved = helper;

    resolved ??= DynamicLibrary.open(
        '/home/simon/programming/goodies.dart/io_uring/native/libdart_io_uring.so');

    if (resolved == null) {
      final location = await Isolate.resolvePackageUri(
          Uri.parse('package:io_uring/src/lib.so'));

      if (location == null) {
        throw StateError('No `library` provided to `runWithIOUring` and none '
            'could be inferred.');
      }

      resolved = DynamicLibrary.open(location.path);
    }

    final binding = Binding(resolved);
    final queue = PollingQueue(binding, alloc);
    return IOUringImpl(queue, alloc);
  }
}
