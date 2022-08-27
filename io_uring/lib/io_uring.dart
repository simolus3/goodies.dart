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

  static Future<IOUring> initialize({Allocator alloc = malloc}) async {
    final path = await Isolate.resolvePackageUri(
        Uri.parse('package:io_uring/src/libdart_io_uring.so'));
    if (path == null) {
      throw StateError('Could not find shared library with io_uring helpers');
    }

    final library = DynamicLibrary.open(path.toFilePath());

    final binding = Binding(library);
    final queue = PollingQueue(binding, alloc);
    return IOUringImpl(queue, alloc);
  }
}
