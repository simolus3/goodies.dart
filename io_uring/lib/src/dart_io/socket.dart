import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import '../io_uring.dart';
import '../linux/socket.dart';
import '../ring/polling_queue.dart';

class _IORingManagedSocket {
  final int fd;
  final IOUringImpl ring;

  _IORingManagedSocket(this.fd, this.ring);

  /// Opens a socket that is not connected or bound to any address.
  static _IORingManagedSocket _createSocket(
      IOUringImpl impl, int domain, int type) {
    final fd = impl.binding.dartio_socket(domain, type, 0)
      ..throwIfError(impl.binding);

    return _IORingManagedSocket(fd, impl);
  }

  _AddressAndLength _convertAddress(InternetAddress addr, int port) {
    Pointer<Void> sockaddr;
    int sockaddrlen;

    // All sockaddr_ types start with a sa_family_t, an unsigned short int.
    // The rest of the structure depends on the address type.
    switch (addr.type) {
      case InternetAddressType.IPv4:
        final ptr = ring.allocator<_sockaddr_in>(1);
        ring.binding.memset(ptr.cast(), 0, sizeOf<_sockaddr_in>());
        ptr.ref
          ..family = AF_INET
          ..address =
              addr.rawAddress.buffer.asByteData().getUint32(0, Endian.host)
          ..port = port.to16BitBigEndian();
        sockaddr = ptr.cast();
        sockaddrlen = sizeOf<_sockaddr_in>();
        break;
      case InternetAddressType.IPv6:
        final ptr = ring.allocator<_sockaddr_in6>(1);
        ring.binding.memset(ptr.cast(), 0, sizeOf<_sockaddr_in6>());

        final ref = ptr.ref
          ..family = AF_INET6
          ..port = port.to16BitBigEndian();

        for (var i = 0; i < 16; i++) {
          ref.addr[i] = addr.rawAddress[i];
        }

        sockaddr = ptr.cast();
        sockaddrlen = sizeOf<_sockaddr_in6>();
        break;
      default:
        throw ArgumentError('Unsupported address $addr');
    }

    return _AddressAndLength(sockaddr, sockaddrlen);
  }

  ConnectionTask<void> _connect(InternetAddress addr, int port) {
    final nativeAddress = _convertAddress(addr, port);

    return ring
        .runCancellable(ring.connect(
            fd, nativeAddress.address, nativeAddress.addressLength))
        .replaceFuture((inner) => inner
            .whenComplete(() => ring.allocator.free(nativeAddress.address)));
  }

  void _bind(InternetAddress addr, int port) {
    final nativeAddress = _convertAddress(addr, port);

    try {
      ring.binding
          .dartio_bind(fd, nativeAddress.address, nativeAddress.addressLength)
          .throwIfError(ring.binding);
    } finally {
      ring.allocator.free(nativeAddress.address);
    }
  }

  void listen(int backlog) {
    ring.binding.dartio_listen(fd, backlog).throwIfError(ring.binding);
  }

  Future<void> _close({bool forRead = false, bool forWrite = false}) {
    if (!forRead && !forWrite) {
      throw ArgumentError('At least one of forRead or forWrite must be set');
    }

    int how;
    if (forRead && forWrite) {
      how = SHUT_RDWR;
    } else if (forWrite) {
      how = SHUT_WR;
    } else {
      how = SHUT_RD;
    }

    return ring.run(ring.shutdown(fd, how));
  }
}

class RingBasedSocket extends Stream<Uint8List> implements Socket {
  final _IORingManagedSocket socket;

  @override
  Encoding encoding = utf8;

  @override
  late final InternetAddress address;

  @override
  late final int port;

  @override
  late final InternetAddress remoteAddress;

  @override
  late final int remotePort;

  final LinkedList<_PendingSocketWrite> _pendingWrites = LinkedList();
  StreamSubscription<List<int>>? _writingStream;
  Completer<void>? _flushCompleter;
  final Completer<void> _writeClosed = Completer();
  ConnectionTask<void>? _currentWrite;

  static const sizeOfReceive = 65536;
  final Pointer<Uint8> _receiveBuffer;
  ConnectionTask<void>? _currentRead;
  final StreamController<Uint8List> _events = StreamController();

  RingBasedSocket(this.socket)
      : _receiveBuffer = socket.ring.allocator(sizeOfReceive) {
    // When we get to this point, we have a fully connected socket so we can
    // query what it is bound to
    final ring = socket.ring;
    final addressBuffer = ring.allocator.allocate<Void>(1024);
    final length = ring.allocator<Uint32>();

    try {
      length.value = 1024;
      ring.binding
          .dartio_getsockname(socket.fd, addressBuffer, length)
          .throwIfError(ring.binding);
      var addr = _DartAddressAndPort.ofNative(addressBuffer);
      address = addr.address;
      port = addr.port;

      length.value = 1024;
      ring.binding
          .dartio_getpeername(socket.fd, addressBuffer, length)
          .throwIfError(ring.binding);
      addr = _DartAddressAndPort.ofNative(addressBuffer);
      remoteAddress = addr.address;
      remotePort = addr.port;
    } finally {
      ring.allocator.free(addressBuffer);
      ring.allocator.free(length);
    }

    _events
      ..onListen = _startListening
      ..onResume = _startListening
      ..onPause = _stopListening
      ..onCancel = _stopListening;
  }

  static Future<ConnectionTask<Socket>> startConnect(
      IOUringImpl ring, dynamic host, int port,
      {dynamic sourceAddress, Duration? timeout}) async {
    List<InternetAddress> resolvedHosts;

    if (host is InternetAddress) {
      resolvedHosts = [host];
    } else if (host is String) {
      resolvedHosts = await InternetAddress.lookup(host);
    } else {
      throw ArgumentError.value(
          host, 'host', 'Must be a string or an internet address');
    }

    // We may have multiple addresses to try out (e.g. because both IPv4 and
    // IPv6 are available from a given [host] name). We start connection tasks
    // in parallel and cancel others when the first one is done.
    final winningSocket = Completer<RingBasedSocket>();
    final tasks = <ConnectionTask<void>>[];
    Timer? timeoutTimer;

    for (final host in resolvedHosts) {
      final socket = _IORingManagedSocket._createSocket(
          ring, host.type.linuxSocketType, SOCK_STREAM);

      final task = socket._connect(host, port);
      tasks.add(task);

      // ignore: unawaited_futures
      task.socket.then(
        (done) {
          tasks.remove(task);

          if (!winningSocket.isCompleted) {
            // This socket was connected first, complete!
            winningSocket.complete(RingBasedSocket(socket));
            timeoutTimer?.cancel();

            // This also means that we have to cancel all other tasks
            for (final remaining in tasks) {
              remaining.cancel();
            }
          } else {
            // Another socket was done first, so close this one.
            socket
                ._close(forRead: true, forWrite: true)
                .catchError((Object ignore) {});
          }
        },
        onError: (Object e, StackTrace s) {
          tasks.remove(task);

          if (tasks.isEmpty && !winningSocket.isCompleted) {
            // All operations failed, so report final failure
            winningSocket.completeError(e, s);
          }
        },
      );
    }

    void cancel() {
      if (!winningSocket.isCompleted) {
        winningSocket.completeError(const CancelledException());

        for (final task in tasks) {
          task.cancel();
        }
      }
    }

    if (timeout != null) {
      timeoutTimer = Timer(timeout, cancel);
    }

    final done = winningSocket.future.then((socket) async {
      if (sourceAddress != null) {
        // Bind socket locally (bind to port 0 to get a random port)
        if (sourceAddress is InternetAddress) {
          socket.socket._bind(sourceAddress, 0);
        } else if (sourceAddress is String) {
          final addresses = await InternetAddress.lookup(sourceAddress);
          for (final address in addresses) {
            socket.socket._bind(address, 0);
          }
        } else {
          throw ArgumentError.value(sourceAddress, 'sourceAddress',
              'Must be an InternetAddress or a string');
        }
      }

      return socket;
    });

    return RingConnectionTask(done, cancel);
  }

  void _startListening() {
    if (_currentRead == null) {
      final task = socket.ring.runCancellable(
          socket.ring.recv(socket.fd, _receiveBuffer.cast(), sizeOfReceive, 0));
      _currentRead = task;

      void finishedReading() {
        _currentRead = null;
        if (_events.hasListener && !_events.isPaused) {
          _startListening();
        }
      }

      task.socket.then((bytesRead) {
        // Copy into a VM-managed buffer
        final buffer =
            Uint8List.fromList(_receiveBuffer.asTypedList(bytesRead));
        _events.add(buffer);
        finishedReading();
      }, onError: (Object error, StackTrace trace) {
        _events.addError(error, trace);
        finishedReading();
      });
    }
  }

  void _stopListening() {
    _currentRead?.cancel();
  }

  void _checkCanAdd() {
    if (_writingStream != null) {
      throw StateError('Cannot add a new event while addStream is active!');
    }

    if (_writeClosed.isCompleted) {
      throw StateError('Cannot add a new event after closing');
    }
  }

  void _startWriting() {
    if (_currentWrite != null || _pendingWrites.isEmpty) return;

    final target = _pendingWrites.first;
    target.didStartWrite = true;

    final op = socket.ring.send(
      socket.fd,
      target.start.elementAt(target.bytesWritten).cast(),
      target.bytesRemaining,
      0,
    );
    final write = socket.ring.runCancellable(op);
    _currentWrite = write;

    void writeFinished() {
      _currentWrite = null;
      socket.ring.allocator.free(target.start);
    }

    write.socket.then((bytesWritten) {
      writeFinished();

      target.bytesWritten += bytesWritten;
      if (target.bytesRemaining == 0) {
        // Target was fully written
        _pendingWrites.remove(target);
      }

      // Start another write operation if necessary
      if (_pendingWrites.isNotEmpty) {
        _startWriting();
      } else {
        _flushCompleter?.complete();
        _flushCompleter = null;
      }
    }, onError: (Object error, StackTrace trace) {
      writeFinished();
      // todo: Error handling?
      Zone.current.handleUncaughtError(error, trace);
    });
  }

  @override
  void add(List<int> data) {
    _checkCanAdd();
    _addInternal(data);
  }

  void _addInternal(List<int> data) {
    final last = _pendingWrites.isEmpty ? null : _pendingWrites.last;
    final allocator = socket.ring.allocator;

    if (last != null && !last.didStartWrite) {
      // Combine two events for efficiency
      final oldLength = last.length;
      final totalLength = oldLength + data.length;
      final oldPtr = last.start;
      final oldData = oldPtr.asTypedList(oldLength);

      final newData = allocator.allocate<Uint8>(totalLength);
      last
        ..start = newData
        ..length = totalLength;

      newData.asTypedList(totalLength)
        ..setRange(0, oldLength, oldData)
        ..setRange(oldLength, totalLength, data);

      allocator.free(oldPtr);
    } else {
      final start = allocator<Uint8>(data.length);
      start.asTypedList(data.length).setAll(0, data);

      _pendingWrites.add(_PendingSocketWrite(start, data.length));
      _startWriting();
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    // We won't be able to send the error over the wire, sooo...
    Zone.current.handleUncaughtError(error, stackTrace ?? StackTrace.current);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    _checkCanAdd();

    final completer = Completer<void>.sync();

    // ignore: cancel_subscriptions
    final sub = _writingStream = stream.listen(
      _addInternal,
      onError: completer.completeError,
      cancelOnError: true,
    );

    sub.asFuture<void>().whenComplete(() {
      _writingStream = null;
      if (!completer.isCompleted) completer.complete();
    });

    return completer.future;
  }

  @override
  Future<void> close() {
    // Note: close() is inherited from IOSink, and should only close the writing
    // end of this socket.
    _writingStream?.cancel();
    _currentWrite?.cancel();

    for (final pending in _pendingWrites) {
      // Don't interfere with pending writes, those buffers will be freed the
      // write completes.
      if (!pending.didStartWrite) {
        socket.ring.allocator.free(pending.start);
      }
    }
    _pendingWrites.clear();

    if (!_writeClosed.isCompleted) {
      _writeClosed.complete(socket._close(forWrite: true));
    }

    return done;
  }

  @override
  Future<void> destroy() async {
    await close();

    _stopListening();
    await _events.close();
    socket.ring.allocator.free(_receiveBuffer);
    await socket._close(forRead: true);
  }

  @override
  Future<void> get done => _writeClosed.future;

  @override
  Future<void> flush() {
    _checkCanAdd();
    return (_flushCompleter ??= Completer()).future;
  }

  @override
  Uint8List getRawOption(RawSocketOption option) {
    final ring = socket.ring;

    final lengthPtr = ring.allocator<Uint32>()..value = option.value.length;
    final data = ring.allocator<Uint8>(option.value.length);

    try {
      ring.binding
          .dartio_getsockopt(
            socket.fd,
            option.level,
            option.option,
            data,
            lengthPtr,
          )
          .throwIfError(ring.binding);

      final value = Uint8List.fromList(data.asTypedList(lengthPtr.value));
      option.value.setAll(0, data.asTypedList(option.value.length));
      return value;
    } finally {
      ring.allocator
        ..free(lengthPtr)
        ..free(data);
    }
  }

  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return _events.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  bool setOption(SocketOption option, bool enabled) {
    if (option == SocketOption.tcpNoDelay) {
      // TCP_NODELAY = 1
      setRawOption(RawSocketOption.fromBool(RawSocketOption.levelTcp, 1, true));
    }
    return false; // todo: implement setOption
  }

  @override
  void setRawOption(RawSocketOption option) {
    final ring = socket.ring;

    final lengthPtr = ring.allocator<Uint32>()..value = option.value.length;
    final data = ring.allocator<Uint8>(option.value.length)
      ..asTypedList(option.value.length).setAll(0, option.value);

    try {
      ring.binding
          .dartio_setsockopt(
              socket.fd, option.level, option.option, data, lengthPtr)
          .throwIfError(ring.binding);
    } finally {
      ring.allocator
        ..free(lengthPtr)
        ..free(data);
    }
  }

  @override
  void write(Object? object) {
    add(encoding.encode(object.toString()));
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = ""]) {
    write(objects.join(separator));
  }

  @override
  void writeCharCode(int charCode) {
    add(encoding.encode(String.fromCharCode(charCode)));
  }

  @override
  void writeln([Object? object = ""]) {
    write(object);
    writeCharCode(10); // LF
  }
}

class _PendingSocketWrite extends LinkedListEntry<_PendingSocketWrite> {
  Pointer<Uint8> start;
  int length;
  int bytesWritten = 0;
  bool didStartWrite = false;

  int get bytesRemaining => length - bytesWritten;

  _PendingSocketWrite(this.start, this.length);
}

class RingBasedServerSocket extends Stream<Socket> implements ServerSocket {
  final _IORingManagedSocket socket;
  // This can be a synchronous controller because we'll only emit events in
  // response to another async operation.
  // Further, it allows us to not enqueue unecessary accept syscalls if the
  // listener pauses in response to an event.
  final StreamController<Socket> controller = StreamController(sync: true);

  final Pointer<Void> addressPtr;
  final Pointer<Uint32> lengthPtr;
  ConnectionTask<int>? _currentAcceptTask;

  @override
  late final InternetAddress address;
  @override
  late final int port;

  RingBasedServerSocket(this.socket)
      : addressPtr = socket.ring.allocator.allocate(1024),
        lengthPtr = socket.ring.allocator() {
    final ring = socket.ring;

    lengthPtr.value = 1024;
    ring.binding
        .dartio_getsockname(socket.fd, addressPtr, lengthPtr)
        .throwIfError(ring.binding);
    final addr = _DartAddressAndPort.ofNative(addressPtr);
    address = addr.address;
    port = addr.port;

    controller
      ..onListen = _startOrResume
      ..onResume = _startOrResume
      ..onPause = _pauseOrCancel
      ..onCancel = _pauseOrCancel;
  }

  static RingBasedServerSocket bind(
      IOUringImpl ring, InternetAddress addr, int port, int backlog) {
    final socket = _IORingManagedSocket._createSocket(
        ring, addr.type.linuxSocketType, SOCK_STREAM)
      .._bind(addr, port)
      ..listen(backlog);

    return RingBasedServerSocket(socket);
  }

  void _startOrResume() {
    if (_currentAcceptTask == null) {
      final task = socket.ring
          .runCancellable(socket.ring.accept(socket.fd, addressPtr, lengthPtr));
      task.socket.then((fd) {
        _currentAcceptTask = null;

        final connectedSocket =
            RingBasedSocket(_IORingManagedSocket(fd, socket.ring));
        controller.add(connectedSocket);

        if (controller.hasListener && !controller.isPaused) {
          // Start another round!
          _startOrResume();
        }
      }, onError: (Object error, StackTrace trace) {
        _currentAcceptTask = null;
        controller.addError(error, trace);

        if (controller.hasListener && !controller.isPaused) {
          _startOrResume();
        }
      });
      _currentAcceptTask = task;
    }
  }

  void _pauseOrCancel() {
    _currentAcceptTask?.cancel();
    _currentAcceptTask = null;
  }

  @override
  Future<ServerSocket> close() async {
    _pauseOrCancel();

    try {
      await socket._close(forRead: true, forWrite: true);
      await controller.close();
      return this;
    } finally {
      socket.ring.allocator
        ..free(addressPtr)
        ..free(lengthPtr);
    }
  }

  @override
  StreamSubscription<Socket> listen(void Function(Socket event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return controller.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}

class _sockaddr_in extends Struct {
  @Uint16()
  external int family;

  @Uint16()
  external int port;

  @Uint32()
  external int address;

  @Array(8)
  external Array<Uint8> padding;
}

class _sockaddr_in6 extends Struct {
  @Uint16()
  external int family;

  @Uint16()
  external int port;

  @Uint32()
  external int flow;

  @Array(16)
  external Array<Uint8> addr;

  @Uint32()
  external int scope;
}

class _AddressAndLength {
  final Pointer<Void> address;
  final int addressLength;

  _AddressAndLength(this.address, this.addressLength);
}

class _DartAddressAndPort {
  final InternetAddress address;
  final int port;

  _DartAddressAndPort(this.address, this.port);

  factory _DartAddressAndPort.ofNative(Pointer<Void> address) {
    final type = address.cast<Uint16>().value;
    switch (type) {
      case AF_INET:
        final data = address.cast<_sockaddr_in>().ref;
        final rawAddress = Uint8List(4);
        rawAddress.buffer.asByteData().setUint32(0, data.address, Endian.host);

        final inetAddress = InternetAddress.fromRawAddress(rawAddress);
        return _DartAddressAndPort(inetAddress, data.port.to16BitHost());
      case AF_INET6:
        final data = address.cast<_sockaddr_in6>().ref;
        final rawAddress = Uint8List(16);
        for (var i = 0; i < 16; i++) {
          rawAddress[i] = data.addr[i];
        }

        final inetAddress = InternetAddress.fromRawAddress(rawAddress);
        return _DartAddressAndPort(inetAddress, data.port.to16BitHost());
      case AF_UNIX:
        break;
    }

    throw ArgumentError('Unsupported native address');
  }
}
