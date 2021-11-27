import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'dart:typed_data';

import 'buffers.dart';
import 'io_uring.dart';
import 'ring/polling_queue.dart';

extension AllocatorUtils on Allocator {
  Pointer<Uint8> allocateBytes(List<int> bytes, [int start = 0, int? end]) {
    final effectiveEnd = end ?? bytes.length;
    final length = effectiveEnd - start;

    final buffer = allocate<Uint8>(length);
    final dartView = buffer.asTypedList(length);

    if (bytes is Uint8List) {
      dartView.setAll(
          0, bytes.buffer.asUint8List(bytes.offsetInBytes + start, length));
    } else {
      for (var i = 0; i < length; i++) {
        dartView[i] = bytes[i + start];
      }
    }

    return buffer;
  }
}

/// Used for debugging purposes.
String bytesToHex(Pointer<NativeType> ptr, int length) {
  final data = ptr.cast<Uint8>().asTypedList(length);
  final charCodes = Uint8List(length * 2);

  const $0 = 0x30;
  const $a = 0x41;

  void writeNibble(int i, int value) {
    if (value > 9) {
      charCodes[i] = $a + (value - 10);
    } else {
      charCodes[i] = $0 + value;
    }
  }

  for (var i = 0; i < length; i++) {
    final byte = data[i];
    writeNibble(2 * i, (byte & 0xF0) >> 4);
    writeNibble(2 * i + 1, byte & 0x0F);
  }

  return String.fromCharCodes(charCodes);
}

// Note: This class is generic because it's shared between files (which are
// a `Stream<List<int>>`) and sockets (which are a `Stream<Uint8List>`).
// We can't make it a `Uint8List` stream in all cases because Dart's generics
// are weird (see e.g. https://github.com/dart-lang/shelf/issues/189)
abstract class IOStream<T extends List<int>> extends Stream<T> {
  // We can make this controller sync because we'll only ever add events in
  // response to other async events.
  // ignore: close_sinks
  final _controller = StreamController<T>(sync: true);
  int? _remainingBytes;
  ConnectionTask<int>? _pendingOperation;

  final IOUringImpl ring;

  bool get supportsFixedReads => true;

  IOStream(this.ring, {int? bytesToRead}) : _remainingBytes = bytesToRead {
    _controller
      ..onListen = () {
        _readAndEmit();
      }
      ..onResume = () {
        if (_pendingOperation == null) {
          _readAndEmit();
        }
      }
      ..onCancel = () {
        _pendingOperation?.cancel();
      };
  }

  Operation<int> read(Pointer<Uint8> buffer, int length);

  Operation<int> readFixed(ManagedBuffer buffer, int length);

  // Emit a chunk, and report whether more data is needed.
  bool _emit(Uint8List chunk) {
    if (chunk.isEmpty) {
      _controller.close(); // EoF reached
      return false;
    } else {
      _controller.add(chunk as T);
      var remaining = _remainingBytes;
      if (remaining != null) {
        remaining -= chunk.length;
        _remainingBytes = remaining;
      }

      if (remaining != null && remaining <= 0) {
        assert(remaining == 0, 'Wrote more data than expected');
        _controller.close();
        return false;
      } else {
        // Fetch again if we have an active listener
        return _controller.hasListener && !_controller.isPaused;
      }
    }
  }

  void _onError(Object error, StackTrace trace) {
    _pendingOperation = null;
    if (error is! CancelledException) {
      _controller.addError(error, trace);
    }

    if (_controller.hasListener && !_controller.isPaused) {
      _readAndEmit();
    }
  }

  void _readAndEmit() {
    assert(_pendingOperation == null, 'Two reads at the same time, no good');

    final currentBuffer = supportsFixedReads ? ring.buffers.useBuffer() : null;
    final remaining = _remainingBytes;

    if (currentBuffer != null) {
      // We have a shared buffer with the Kernel, nice! Then we only need a
      // single copy into the Dart heap.
      var length = currentBuffer.buffer.ref.iov_len;
      final remaining = _remainingBytes;
      if (remaining != null) {
        length = min(length, remaining);
      }

      final task = _pendingOperation =
          ring.runCancellable(readFixed(currentBuffer, length));
      task.socket.then(
        (bytesRead) {
          // Copy into Dart heap
          final chunk = Uint8List.fromList(currentBuffer.buffer.ref.iov_base
              .cast<Uint8>()
              .asTypedList(bytesRead));

          _pendingOperation = null;
          final fetchAgain = _emit(chunk);
          if (fetchAgain) _readAndEmit();
        },
        onError: _onError,
      ).whenComplete(() => ring.buffers.returnBuffer(currentBuffer));
    } else {
      // Slightly slower path, read into a general buffer
      const chunkSize = 65536;
      final buffer = ring.allocator<Uint8>(chunkSize);

      var length = chunkSize;
      if (remaining != null) {
        length = min(length, remaining);
      }

      final task =
          _pendingOperation = ring.runCancellable(read(buffer, length));
      task.socket.then(
        (bytesRead) {
          final chunk = Uint8List.fromList(buffer.asTypedList(bytesRead));

          _pendingOperation = null;
          final fetchAgain = _emit(chunk);
          if (fetchAgain) _readAndEmit();
        },
        onError: _onError,
      ).whenComplete(() => ring.allocator.free(buffer));
    }
  }

  @override
  StreamSubscription<T> listen(void Function(T event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return _controller.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  /// Synchronously reads a byte.
  ///
  /// Using this and the async API is undefined behavior.
  int readByteSync() {
    final buffer = ring.allocator<Uint8>(1);
    try {
      final bytesRead = ring.runSync(read(buffer, 1));

      if (bytesRead == 0) return -1;
      return buffer[0];
    } finally {
      ring.allocator.free(buffer);
    }
  }

  void close() {
    _pendingOperation?.cancel();
    _controller.close();
  }
}
