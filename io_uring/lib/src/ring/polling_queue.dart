import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../utils.dart';
import 'binding.dart';

const bool _traceOperations =
    bool.fromEnvironment('io_uring.trace', defaultValue: false);

class PollingQueue {
  final Binding binding;
  final Map<int, Completer<int>> _ongoingOperations = {};
  int _operationId = 0;
  int _pendingOperations = 0;
  bool _closed = false;
  bool _addedTaskDuringFetch = false;
  bool _startedSynchronousPollDuringFetch = false;

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
      // Reading structs is somehow expensive, so let's only do that once
      : _submissions = ring.submissions,
        _completions = ring.completions;

  void _startTimerIfNecessary() {
    if (_pendingOperations > 0 && _timer == null) {
      if (_traceOperations) {
        print('Starting fetch timer');
      }

      _timer = Timer.periodic(Duration.zero, (timer) {
        _fetch();
      });
    }
  }

  void _stopTimerIfNecessary() {
    if (_pendingOperations == 0) {
      if (_traceOperations) {
        print('Stopping fetch timer');
      }
      _timer?.cancel();
      _timer = null;
    }
  }

  void _fetch() {
    _addedTaskDuringFetch = false;
    _startedSynchronousPollDuringFetch = false;

    final completions = ring.completions;
    final originalHead = completions.head.value;
    var head = originalHead;
    final ringMask = completions.ring_mask.value;
    var processed = 0;

    // We're on a ring buffer, so if head == tail we caught up.
    while (head != completions.tail.value) {
      final cqe = completions.cqes[head & ringMask];

      head++;
      ring.completions.head.value = head;

      final FutureOr<int> value;
      if (_addedTaskDuringFetch) {
        value = Future.value(cqe.res);
      } else {
        value = cqe.res;
      }

      final operation = _ongoingOperations.remove(cqe.user_data);
      if (_traceOperations) {
        print('completing ${cqe.user_data} with ${cqe.res}, '
            'matched operation is $operation');
      }

      if (operation != null) {
        _pendingOperations--;
        operation.complete(value);
      }

      processed++;
      if (processed == 100 || _startedSynchronousPollDuringFetch) {
        // We don't want to process too many events in one iteration, we're
        // completing synchronously and this blocks up the event queue.
        break;
      }
    }

    _stopTimerIfNecessary();
  }

  Future<int> submitAndFetchAsync(void Function(io_uring_sqe sqe) updates) {
    final id = submitOnly(updates);
    return completion(id);
  }

  void cancel(int id) {
    if (_traceOperations) {
      print('cancelling $id');
    }

    final cancelId = submitOnly((sqe) => sqe
      ..op = IORING_OP.ASYNC_CANCEL
      ..addr = id);

    completion(cancelId).then((cancelResult) {
      // If not -ENOENT, a cancellation was attempted.
      if (cancelResult != -2) {
        final pending = _ongoingOperations.remove(id);
        if (pending != null) {
          pending.completeError(const CancelledException());
          _pendingOperations--;
          _stopTimerIfNecessary();
        }
      }
    });
  }

  /// Returns a future that completes when the request with the id [id] has
  /// completed.
  ///
  /// This should be called synchronously after submitting the entry.
  Future<int> completion(int id) {
    // We _really_ want to be using synchronous primitives where possible, the
    // overhead of async operations dominates benchmarks.
    // We make sure that this future does not complete synchronously by:
    //  - using a timer to fetch events, or completing asynchronously in
    //   [waitForEvent]
    //  - stopping a timer run if completing a future synchronously adds a new
    //    completer.
    final completer = _ongoingOperations[id] = Completer.sync();
    _pendingOperations++;
    _startTimerIfNecessary();
    return completer.future;
  }

  int submitOnly(void Function(io_uring_sqe sqe) updates, {int waitFor = 0}) {
    if (_closed) {
      throw StateError('Ring was closed already');
    }

    final submissions = _submissions;
    final head = submissions.head.value;
    final tail = submissions.tail.value;
    final next = tail + 1;

    if (next - head > submissions.entry_count.value) {
      throw StateError('Submission queue is full');
    }

    // Write the event into the right submission queue index
    final index = tail & submissions.ring_mask.value;
    final sqePtr = submissions.sqes.elementAt(index);

    binding.memset(sqePtr.cast(), 0, sizeOf<io_uring_sqe>());

    final sqe = sqePtr.ref;
    updates(sqe);
    final id = sqe.userData = _operationId++;

    if (_traceOperations) {
      final op = sqe.op;
      print('submit (head = $head, i = $index, op = $op, k = $head): 0x' +
          bytesToHex(sqePtr, sizeOf<io_uring_sqe>()));
    }

    // Since we're using synchronous completers, we may add a new task
    // synchronously while processing a completion event. That's fine, but we
    // should then stop handing out completions synchronously to make sure that
    // this event doesn't complete synchronously after being added.
    _addedTaskDuringFetch = true;

    // Submit the event to the Kernel!
    submissions.tail.value = next;
    final result = binding.dartio_uring_enter(ring.fd, 1, waitFor, 0);

    if (result < 0) {
      throw IOUringException('Could not add entry to submission queue');
    } else {
      return id;
    }
  }

  int waitForEvent(int id) {
    _startedSynchronousPollDuringFetch = true;
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
      final cqePtr =
          completions.cqes.elementAt(head & completions.ring_mask.value);
      final cqe = cqePtr.ref;
      head++;

      if (_traceOperations) {
        print('io_uring done: 0x' + bytesToHex(cqePtr, sizeOf<io_uring_cqe>()));
      }

      if (cqe.user_data == id) {
        result = cqe.res;
        break;
      } else if (_ongoingOperations.containsKey(cqe.user_data)) {
        _pendingOperations--;
        // waitForEvent is called synchronously and we're using sync completers,
        // so let's add an async delay here to ensure our Future's behave well.
        _ongoingOperations
            .remove(cqe.user_data)!
            .complete(Future.value(cqe.res));
      } else {
        throw AssertionError('Unexpected completion event: ${cqe.user_data} '
            'while waiting for $id');
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
