import 'dart:ffi';

import 'package:ffi/ffi.dart';

// Don't use isLeaf when profiling, see https://dartbug.com/47594
const _profile = bool.hasEnvironment('profile');
const _canUseIsLeaf = !_profile;

class io_uring_sqe extends Struct {
  @Uint8()
  external int opcode;
  @Uint8()
  external int flags;
  @Uint16()
  external int ioprio;
  @Int32()
  external int fd;
  @Uint64()
  external int off;
  @Uint64()
  external int addr;
  @Uint32()
  external int len;

  // Defined as a union in C
  @Uint32()
  external int x_flags;

  @Uint64()
  external int userData;

  external _io_uring_sqe_additional_or_padding additional;
}

class _io_uring_sqe_additional extends Struct {
  @Uint16()
  external int buf_index;
  @Uint16()
  external int personality;
  @Int32()
  external int splice_fd_in;
}

class _io_uring_sqe_additional_or_padding extends Union {
  external _io_uring_sqe_additional additional;

  @Array(3)
  external Array<Uint64> padding;
}

class io_uring_cqe extends Struct {
  @Uint64()
  external int user_data;
  @Int32()
  external int res;
  @Uint32()
  external int flags;
}

class dart_io_ring_submit extends Struct {
  external Pointer<Uint32> head;
  external Pointer<Uint32> tail;
  external Pointer<Uint32> ring_mask;
  external Pointer<Uint32> entry_count;
  external Pointer<Uint32> flags;
  external Pointer<Uint32> array;
  external Pointer<io_uring_sqe> sqes;
}

class dart_io_ring_complete extends Struct {
  external Pointer<Uint32> head;
  external Pointer<Uint32> tail;
  external Pointer<Uint32> ring_mask;
  external Pointer<Uint32> entry_count;
  external Pointer<io_uring_cqe> cqes;
}

class dart_io_ring extends Struct {
  @Int32()
  external int fd;
  external dart_io_ring_submit submissions;
  external dart_io_ring_complete completions;
}

typedef _setup = Pointer<dart_io_ring> Function(Pointer<Pointer<Int8>>);
typedef _enter_native = Int32 Function(Int32, Uint32, Uint32, Uint32);
typedef _enter_dart = int Function(int, int, int, int);
typedef _register_native = Int32 Function(
    Pointer<dart_io_ring>, Uint32, Pointer<NativeType>, Uint32);
typedef _register_dart = int Function(
    Pointer<dart_io_ring>, int, Pointer<NativeType>, int);
typedef _socket_native = Int32 Function(Int32, Int32, Int32);
typedef _socket_dart = int Function(int, int, int);
typedef _strerror_native = Pointer<Utf8> Function(Int32);
typedef _strerror_dart = Pointer<Utf8> Function(int);
typedef _umask_native = Uint32 Function(Uint32);
typedef _umask_dart = int Function(int);
typedef _mmap_native = Pointer<Void> Function(
    Pointer<Void>, IntPtr, Int32, Int32, Int32, IntPtr);
typedef _mmap_dart = Pointer<Void> Function(
    Pointer<Void>, int, int, int, int, int);
typedef _memset_native = Pointer<Void> Function(
    Pointer<Void>, Int32 c, IntPtr n);
typedef _memset_dart = Pointer<Void> Function(Pointer<Void>, int c, int n);

class Binding {
  final DynamicLibrary library;

  final _setup dartio_uring_setup;
  final _register_dart dartio_uring_register;
  final _enter_dart dartio_uring_enter;
  final _socket_dart dartio_socket;
  final _strerror_dart strerror;
  final _strerror_dart sterrorname_np;
  final _umask_dart umask;
  final _mmap_dart mmap;
  final _memset_dart memset;

  Binding(this.library)
      : dartio_uring_setup = library.lookupFunction<_setup, _setup>(
            'dartio_uring_setup',
            isLeaf: _canUseIsLeaf),
        dartio_uring_enter = library.lookupFunction<_enter_native, _enter_dart>(
            'dartio_uring_enter',
            isLeaf: _canUseIsLeaf),
        dartio_uring_register =
            library.lookupFunction<_register_native, _register_dart>(
                'dartio_uring_register',
                isLeaf: _canUseIsLeaf),
        dartio_socket = library.lookupFunction<_socket_native, _socket_dart>(
            'dartio_socket',
            isLeaf: _canUseIsLeaf),
        strerror = library.lookupFunction<_strerror_native, _strerror_dart>(
            'strerror',
            isLeaf: _canUseIsLeaf),
        sterrorname_np = library
            .lookupFunction<_strerror_native, _strerror_dart>('strerrorname_np',
                isLeaf: _canUseIsLeaf),
        umask = library.lookupFunction<_umask_native, _umask_dart>('umask',
            isLeaf: _canUseIsLeaf),
        mmap = library.lookupFunction<_mmap_native, _mmap_dart>('mmap',
            isLeaf: _canUseIsLeaf),
        memset = library.lookupFunction<_memset_native, _memset_dart>('memset',
            isLeaf: _canUseIsLeaf);
}

enum IORING_OP {
  NOP,
  READV,
  WRITEV,
  FSYNC,
  READ_FIXED,
  WRITE_FIXED,
  POLL_ADD,
  POLL_REMOVE,
  SYNC_FILE_RANGE,
  SENDMSG,
  RECVMSG,
  TIMEOUT,
  TIMEOUT_REMOVE,
  ACCEPT,
  ASYNC_CANCEL,
  LINK_TIMEOUT,
  CONNECT,
  FALLOCATE,
  OPENAT,
  CLOSE,
  FILES_UPDATE,
  STATX,
  READ,
  WRITE,
  FADVISE,
  MADVISE,
  SEND,
  RECV,
  OPENAT2,
  EPOLL_CTL,
  SPLICE,
  PROVIDE_BUFFERS,
  REMOVE_BUFFERS,
  TEE,
  SHUTDOWN,
  RENAMEAT,
  UNLINKAT,
  LAST,
}

extension Operation on io_uring_sqe {
  IORING_OP get op => IORING_OP.values[opcode];
  set op(IORING_OP op) => opcode = op.index;
}
