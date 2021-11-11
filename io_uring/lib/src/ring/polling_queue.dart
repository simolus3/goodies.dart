import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'binding.dart';

class PollingQueue {
  final Binding binding;
  final Map<int, Completer<int>> _ongoingOperations = {};
  int _operationId = 0;
  int _pendingOperations = 0;
  bool _closed = false;

  final Pointer<dart_io_ring> ringPtr;
  final dart_io_ring ring;

  final dart_io_ring_submit _submissions;
  final dart_io_ring_complete _completions;

  Timer? _timer;

  factory PollingQueue(Binding binding, Allocator alloc) {
    final out = alloc<Pointer<NativeType>>(1);
    final utf8Out = out.cast<Pointer<Utf8>>();
    out.value = nullptr;
    final ringPtr = binding.dartio_uring_setup(out.cast());
    final ring = ringPtr.ref;

    if (out.value != nullptr) {
      final message = utf8Out.value.toDartString();
      alloc.free(out);
      throw IOUringException(message);
    }

    // io_uring provides a level of indirection between sqe offsets and ring
    // indices. We don't use this feature, so make the array an identity mapping
    // now.
    final count = ring.submissions.entry_count.value;
    for (var i = 0; i < count; i++) {
      ring.submissions.array[i] = i;
    }

    return PollingQueue._(binding, ringPtr, ring);
  }

  PollingQueue._(this.binding, this.ringPtr, this.ring)
      // Reading structs is somehow expensive, so let's only do that once if we
      // can...
      : _submissions = ring.submissions,
        _completions = ring.completions;

  void _startTimerIfNecessary() {
    if (_pendingOperations > 0 && _timer == null) {
      _timer = Timer.periodic(Duration.zero, (timer) {
        _fetch();
      });
    }
  }

  void _stopTimerIfNecessary() {
    if (_pendingOperations == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _fetch() {
    final completions = ring.completions;
    final originalHead = completions.head.value;
    var head = originalHead;

    try {
      // We're on a ring buffer, so if head == tail we caught up.
      while (head != completions.tail.value) {
        final cqe = completions.cqes[head & completions.ring_mask.value];
        _pendingOperations--;
        _ongoingOperations.remove(cqe.user_data)!.complete(cqe.res);

        head++;
      }
    } finally {
      if (originalHead != head) {
        ring.completions.head.value = head;
      }
    }

    _stopTimerIfNecessary();
  }

  Future<int> submitAndFetchAsync(void Function(io_uring_sqe sqe) updates) {
    final id = submitOnly(updates);
    return completion(id);
  }

  void cancel(int id) {
    submitOnly((sqe) => sqe
      ..op = IORING_OP.ASYNC_CANCEL
      ..addr = id);

    final pending = _ongoingOperations.remove(id);
    if (pending != null) {
      pending.completeError(const CancelledException());
      _pendingOperations--;
      _stopTimerIfNecessary();
    }
  }

  /// Returns a future that completes when the request with the id [id] has
  /// completed.
  ///
  /// This should be called immediately after registering the request.
  Future<int> completion(int id) {
    final completer = _ongoingOperations[id] = Completer();
    _pendingOperations++;
    _startTimerIfNecessary();
    return completer.future;
  }

  int submitOnly(void Function(io_uring_sqe sqe) updates) {
    if (_closed) {
      throw StateError('Ring was closed already');
    }

    final submissions = _submissions;
    final tail = submissions.tail.value;

    // Write the event into the right submission queue index
    final index = tail & submissions.ring_mask.value;
    final sqePtr = submissions.sqes.elementAt(index);
    binding.memset(sqePtr.cast(), 0, sizeOf<io_uring_cqe>());

    final sqe = sqePtr.ref;
    updates(sqe);
    final id = sqe.userData = _operationId++;

    // Submit the event to the Kernel!
    submissions.tail.value = tail + 1;
    final result = binding.dartio_uring_enter(ring.fd, 1, 0, 0);

    if (result < 0) {
      throw IOUringException('Could not add entry to submission queue');
    } else {
      return id;
    }
  }

  int waitForEvent(int id) {
    final completions = _completions;
    final originalHead = completions.head.value;
    var head = originalHead;

    while (head == completions.tail.value) {
      // Synchronously wait for this to change (0 to submit, wait for 1)
      binding.dartio_uring_enter(ring.fd, 0, 1, 0);
    }

    late int result;

    // We're on a ring buffer, so if head == tail we caught up.
    while (head != completions.tail.value) {
      final cqe = completions.cqes[head & completions.ring_mask.value];
      head++;

      if (cqe.user_data == id) {
        result = cqe.res;
        break;
      } else if (_ongoingOperations.containsKey(cqe.user_data)) {
        _pendingOperations--;
        _ongoingOperations.remove(cqe.user_data)!.complete(cqe.res);
      } else {
        throw AssertionError('Unexpected completion event: ${cqe.user_data}');
      }
    }

    if (originalHead != head) {
      ring.completions.head.value = head;
    }

    _stopTimerIfNecessary();
    return result;
  }

  void close() {
    _closed = true;
    _timer?.cancel();
    _pendingOperations = 0;
    binding.dartio_close(ringPtr);

    for (final pending in _ongoingOperations.values) {
      pending.completeError(const CancelledException());
    }
    _ongoingOperations.clear();
  }
}

class IOUringException implements IOException {
  final String message;

  IOUringException(this.message);

  @override
  String toString() {
    return 'io_uring error: $message';
  }
}

class CancelledException implements Exception {
  const CancelledException();

  @override
  String toString() => 'cancelled';
}
