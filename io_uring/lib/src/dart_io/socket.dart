import 'dart:async';
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

  InternetAddress? connectedAddress;

  _IORingManagedSocket(this.fd, this.ring);

  /// Opens a socket that is not connected or bound to any address.
  static _IORingManagedSocket _createSocket(
      IOUringImpl impl, int domain, int type) {
    final fd = impl.binding.dartio_socket(domain, type, 0)
      ..throwIfError(impl.binding);

    return _IORingManagedSocket(fd, impl);
  }

  ConnectionTask<void> _connect(InternetAddress addr, int port) {
    connectedAddress = addr;

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
          ..port = htons(port);
        sockaddr = ptr.cast();
        sockaddrlen = sizeOf<_sockaddr_in>();

        break;
      default:
        throw ArgumentError('Unsupported address $this');
    }

    return ring
        .runCancellable(ring.connect(fd, sockaddr, sockaddrlen))
        .replaceFuture(
            (inner) => inner.whenComplete(() => ring.allocator.free(sockaddr)));
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

  RingBasedSocket(this.socket);

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

    final winningSocket = Completer<Socket>();
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

    return RingConnectionTask(winningSocket.future, cancel);
  }

  @override
  void add(List<int> data) {
    // TODO: implement add
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    // TODO: implement addError
  }

  @override
  Future addStream(Stream<List<int>> stream) {
    // TODO: implement addStream
    throw UnimplementedError();
  }

  @override
  InternetAddress get address => socket.connectedAddress!;

  @override
  Future close() {
    // TODO: implement close
    throw UnimplementedError();
  }

  @override
  void destroy() {
    // TODO: implement destroy
  }

  @override
  // TODO: implement done
  Future get done => throw UnimplementedError();

  @override
  Future flush() {
    // TODO: implement flush
    throw UnimplementedError();
  }

  @override
  Uint8List getRawOption(RawSocketOption option) {
    // TODO: implement getRawOption
    throw UnimplementedError();
  }

  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    // TODO: implement listen
    throw UnimplementedError();
  }

  @override
  // TODO: implement port
  int get port => throw UnimplementedError();

  @override
  // TODO: implement remoteAddress
  InternetAddress get remoteAddress => throw UnimplementedError();

  @override
  // TODO: implement remotePort
  int get remotePort => throw UnimplementedError();

  @override
  bool setOption(SocketOption option, bool enabled) {
    // TODO: implement setOption
    throw UnimplementedError();
  }

  @override
  void setRawOption(RawSocketOption option) {
    // TODO: implement setRawOption
  }

  @override
  void write(Object? object) {
    // TODO: implement write
  }

  @override
  void writeAll(Iterable objects, [String separator = ""]) {
    // TODO: implement writeAll
  }

  @override
  void writeCharCode(int charCode) {
    // TODO: implement writeCharCode
  }

  @override
  void writeln([Object? object = ""]) {
    // TODO: implement writeln
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
