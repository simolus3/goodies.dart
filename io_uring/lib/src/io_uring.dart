import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../io_uring.dart';
import 'buffers.dart';
import 'linux/file.dart';
import 'linux/nmap.dart';
import 'linux/stat.dart';
import 'ring/binding.dart';
import 'ring/polling_queue.dart';

class IOUringImpl implements IOUring {
  final PollingQueue queue;
  final Zone creationZone;
  final Allocator allocator;
  final Binding binding;
  SharedBuffers buffers = const SharedBuffers([]);

  late final int _defaultMode;

  IOUringImpl(this.queue, this.allocator)
      : creationZone = Zone.current,
        binding = queue.binding {
    // umask returns the previous mode, so we call it twice to learn the value
    // without changing it.
    _defaultMode = binding.umask(0);
    binding.umask(_defaultMode);

//    createSharedBuffers();
  }

  void createSharedBuffers(
      {int bufferSize = 32 * 1024, int amountOfBuffers = 2}) {
    final totalSize = bufferSize * amountOfBuffers;
    final start = binding
        .mmap(nullptr.cast(), totalSize, PROT_READ | PROT_WRITE,
            MAP_ANON | MAP_SHARED, -1, 0)
        .cast<Uint8>();
    if (start.address <= 0) {
      throw IOUringException('Could not map shared buffers: ');
    }

    final iovecs = allocator<iovec>(amountOfBuffers);
    for (var i = 0; i < amountOfBuffers; i++) {
      iovecs[i]
        ..iov_base = start.elementAt(i * bufferSize).cast()
        ..iov_len = bufferSize;
    }

    // Register those buffers with the Kernel (0 == IORING_REGISTER_BUFFERS)
    final result = binding.dartio_uring_register(
        queue.ringPtr, 0, iovecs, amountOfBuffers);
    if (result < 0) {
      final msg = binding.strerror(-result).toDartString();
      throw IOUringException('Could not register shared buffers: $msg');
    }

    buffers = SharedBuffers([
      for (var i = 0; i < amountOfBuffers; i++)
        ManagedBuffer(iovecs.elementAt(i), i),
    ]);
  }

  T escape<T>(T Function() body) {
    return creationZone.run(body);
  }

  T Function(A) escaped1<T, A>(T Function(A) body) {
    return creationZone.bindUnaryCallback(body);
  }

  ConnectionTask<T> runCancellable<T>(Operation<T> op) {
    final id = queue.submitOnly(op.create);

    return RingConnectionTask(
      _interpretResultAsync(queue.completion(id), op),
      () => queue.cancel(id),
    );
  }

  Future<T> run<T>(Operation<T> op) {
    return _interpretResultAsync(queue.submitAndFetchAsync(op.create), op);
  }

  Future<T> _interpretResultAsync<T>(Future<int> syscall, Operation<T> op) {
    return syscall
        .errorCodesAsErrors(binding, op.failureDescription ?? '', op.path)
        .then(op.interpretResult)
        .whenComplete(op.close);
  }

  T runSync<T>(Operation<T> op) {
    try {
      final id = queue.submitOnly(op.create);
      final result = queue.waitForEvent(id)
        ..throwIfError(binding, op.failureDescription ?? '', op.path);
      return op.interpretResult(result);
    } finally {
      op.close();
    }
  }

  Operation<void> nop() => const _Nop();

  Operation<FileStat> stat(String path, {bool followLinks = true}) {
    final statResult = allocator<statx>(1);
    final name = path.toNativeUtf8(allocator: allocator);

    return Operation(
      create: (sqe) => sqe
        ..op = IORING_OP.STATX
        ..fd = 0
        ..addr = name.cast().address
        ..x_flags = followLinks ? 0 : AT_SYMLINK_NOFOLLOW
        ..len = 0x000007ff // STATX_BASIC_STATS
        ..off = statResult.address,
      interpretResult: (_) => statResult.ref.toFileStat(),
      failureDescription: 'Could not stat',
      path: path,
      close: () => allocator
        ..free(statResult)
        ..free(name),
    );
  }

  Operation<int> openAt2(
    String pathname, {
    int dirfd = AT_FDCWD,
    int flags = O_RDONLY,
    int mode = 0,
    int resolve = 0,
  }) {
    final nameptr = pathname.toNativeUtf8(allocator: allocator);
    final how = allocator<open_how>(1);
    how.ref
      ..flags = flags
      ..mode = mode
      ..resolve = resolve;

    return Operation(
      path: pathname,
      failureDescription: 'Could not open file',
      interpretResult: (fd) => fd,
      create: (sqe) => sqe
        ..op = IORING_OP.OPENAT2
        ..fd = dirfd
        ..addr = nameptr.address
        ..len = sizeOf<open_how>()
        ..off = how.address,
      close: () => allocator
        ..free(nameptr)
        ..free(how),
    );
  }

  Operation<void> renameat2(
    String oldPath,
    String newPath, {
    int oldDirFd = AT_FDCWD,
    int newDirFd = AT_FDCWD,
  }) {
    final oldPathPtr = oldPath.toNativeUtf8(allocator: allocator);
    final newPathPtr = newPath.toNativeUtf8(allocator: allocator);

    return Operation(
      failureDescription: 'Could not rename from $oldPath',
      path: newPath,
      interpretResult: (_) {},
      create: (sqe) => sqe
        ..op = IORING_OP.RENAMEAT
        ..fd = oldDirFd
        ..addr = oldPathPtr.address
        ..len = newDirFd
        ..off = newPathPtr.address, // note: off and addr are in a union
      close: () => allocator
        ..free(oldPathPtr)
        ..free(newPathPtr),
    );
  }

  Operation<void> close(int fd, String pathname) {
    return Operation(
      create: (sqe) => sqe
        ..op = IORING_OP.CLOSE
        ..fd = fd,
      interpretResult: (_) {},
      failureDescription: 'Could not close file',
      path: pathname,
    );
  }

  Operation<void> fsync(int fd, String pathname) {
    return Operation(
      create: (sqe) => sqe
        ..op = IORING_OP.FSYNC
        ..fd = fd,
      interpretResult: (_) {},
      failureDescription: 'Sync failed',
      path: pathname,
    );
  }

  Operation<int> read(int fd, Pointer<NativeType> ptr, int length,
      {int offset = -1, String? path}) {
    return Operation(
      failureDescription: 'Could not read',
      path: path,
      create: (sqe) => sqe
        ..op = IORING_OP.READ
        ..fd = fd
        ..addr = ptr.address
        ..len = length
        ..off = offset,
      interpretResult: (v) => v,
    );
  }

  Operation<int> readFixed(int fd, ManagedBuffer buffer, int length,
      {int offset = -1, String? path}) {
    assert(length <= buffer.buffer.ref.iov_len, 'Overflow');

    return Operation(
      failureDescription: 'Could not read',
      path: path,
      create: (sqe) => sqe
        ..op = IORING_OP.READ_FIXED
        ..fd = fd
        ..addr = buffer.buffer.ref.iov_base.address
        ..additional.additional.buf_index = buffer.index
        ..len = length
        ..off = offset,
      interpretResult: (v) => v,
    );
  }

  Operation<int> write(int fd, Pointer<NativeType> ptr, int length,
      {int offset = -1, String? path}) {
    return Operation(
      failureDescription: 'Could not write',
      path: path,
      create: (sqe) => sqe
        ..op = IORING_OP.WRITE
        ..fd = fd
        ..addr = ptr.address
        ..len = length
        ..off = offset,
      interpretResult: (v) => v,
    );
  }

  Operation<int> writeFixed(int fd, ManagedBuffer buffer, int length,
      {int offset = -1, int offsetInBuffer = 0, String? path}) {
    return Operation(
      failureDescription: 'Could not write',
      path: path,
      create: (sqe) => sqe
        ..op = IORING_OP.WRITE_FIXED
        ..fd = fd
        ..addr = buffer.buffer.ref.iov_base.address + offsetInBuffer
        ..additional.additional.buf_index = buffer.index
        ..len = length
        ..off = offset,
      interpretResult: (v) => v,
    );
  }

  Operation<int> connect(int socketFd, Pointer<Void> sockaddr, int sockaddlen) {
    return Operation(
      create: (sqe) => sqe
        ..op = IORING_OP.CONNECT
        ..fd = socketFd
        ..addr = sockaddr.address
        ..off = sockaddlen,
      interpretResult: (v) => v,
    );
  }

  Operation<int> shutdown(int socketFd, int how) {
    return Operation(
      create: (sqe) => sqe
        ..op = IORING_OP.SHUTDOWN
        ..fd = socketFd
        ..len = how,
      interpretResult: (v) => v,
    );
  }
}

abstract class Operation<T> {
  void create(io_uring_sqe sqe);
  T interpretResult(int callResult);
  void close();

  final String? failureDescription;
  final String? path;

  factory Operation({
    required void Function(io_uring_sqe sqe) create,
    required T Function(int callResult) interpretResult,
    void Function() close = _doNothing,
    String? failureDescription,
    String? path,
  }) {
    return _ClosureOperation(
        create, interpretResult, close, failureDescription, path);
  }

  const Operation._(this.failureDescription, this.path);

  static void _doNothing() {}
}

class _ClosureOperation<T> extends Operation<T> {
  final void Function(io_uring_sqe) _create;
  final T Function(int) _interpretResult;
  final void Function() _close;

  _ClosureOperation(this._create, this._interpretResult, this._close,
      String? failureDescription, String? path)
      : super._(failureDescription, path);

  @override
  void create(io_uring_sqe sqe) {
    _create(sqe);
  }

  @override
  T interpretResult(int callResult) => _interpretResult(callResult);

  @override
  void close() => _close();
}

class _Nop extends Operation<void> {
  const _Nop() : super._(null, null);

  @override
  void close() {}

  @override
  void create(io_uring_sqe sqe) {
    sqe.op = IORING_OP.NOP;
  }

  @override
  void interpretResult(int callResult) {}
}

extension InterpretResultCodes on int {
  void throwIfError(Binding binding, [String message = '', String? path]) {
    if (this < 0) {
      final error = -this;
      final errorName = binding.sterrorname_np(error).toDartString();
      final errorMessage = binding.strerror(error).toDartString();

      throw FileSystemException(
          message, path, OSError('$errorMessage ($errorName)', error));
    }
  }
}

extension on Future<int> {
  Future<int> errorCodesAsErrors(Binding binding,
      [String message = '', String? path]) {
    return then((result) => result..throwIfError(binding, message, path));
  }
}

extension ComposeTasks<T> on ConnectionTask<T> {
  ConnectionTask<T2> replaceFuture<T2>(Future<T2> Function(Future<T>) map) {
    return RingConnectionTask<T2>(map(socket), cancel);
  }
}

// ConnectionTask has a private constructor in `dart:io`...
class RingConnectionTask<T> implements ConnectionTask<T> {
  @override
  final Future<T> socket;
  final void Function() _onCancel;

  RingConnectionTask(this.socket, this._onCancel);

  @override
  void cancel() => _onCancel();
}
