import 'dart:io';

import '../../io_uring.dart';
import '../io_uring.dart';
import 'file_system_entity.dart';
import 'file_system_entity.dart' as fse;
import 'socket.dart';
import 'stdio.dart';

T runWithIOUring<T>(T Function() body, IOUring uring) {
  final impl = uring as IOUringImpl;

  return IOOverrides.runWithIOOverrides(body, _RingOverrides(impl));
}

class _RingOverrides extends IOOverrides {
  final IOUringImpl ring;

  @override
  late final Stdin stdin = RingBasedStdin(super.stdin, ring);

  _RingOverrides(this.ring);

  @override
  Future<FileStat> stat(String path, {bool followLinks = false}) {
    return fse.stat(ring, path, followLinks);
  }

  @override
  FileStat statSync(String path, {bool followLinks = false}) {
    return fse.statSync(ring, path, followLinks);
  }

  @override
  Future<FileSystemEntityType> fseGetType(String path, bool followLinks) async {
    final result = await stat(path, followLinks: followLinks);
    return result.type;
  }

  @override
  FileSystemEntityType fseGetTypeSync(String path, bool followLinks) {
    return statSync(path, followLinks: followLinks).type;
  }

  @override
  Directory createDirectory(String path) {
    return wrapDirectory(ring, ring.escape(() => Directory(path)));
  }

  @override
  File createFile(String path) {
    return wrapFile(ring, ring.escape(() => File(path)));
  }

  @override
  Link createLink(String path) {
    return wrapLink(ring, ring.escape(() => Link(path)));
  }

  @override
  Future<Socket> socketConnect(dynamic host, int port,
      {dynamic sourceAddress, int? sourcePort, Duration? timeout}) {
    return socketStartConnect(host, port,
            sourceAddress: sourceAddress, timeout: timeout)
        .then((task) => task.socket);
  }

  @override
  Future<ConnectionTask<Socket>> socketStartConnect(dynamic host, int port,
      {dynamic sourceAddress, int? sourcePort, Duration? timeout}) {
    return RingBasedSocket.startConnect(ring, host, port,
        sourceAddress: sourceAddress);
  }

  @override
  Future<ServerSocket> serverSocketBind(dynamic address, int port,
      {int backlog = 0, bool v6Only = false, bool shared = false}) async {
    InternetAddress? target;

    if (shared) {
      throw UnsupportedError(
          'Shared socket servers are not supported with io_uring');
    }

    if (address is InternetAddress) {
      if (v6Only && address.type != InternetAddressType.IPv6) {
        throw ArgumentError(
            'Address $address is not an IPv6 address, but v6only was set');
      }

      target = address;
    } else if (address is String) {
      final addresses = await InternetAddress.lookup(address);
      for (final address in addresses) {
        if (!v6Only || address.type == InternetAddressType.IPv6) {
          target = address;
          break;
        }
      }
    } else {
      throw ArgumentError.value(
          address, 'address', 'Must be an address or a string');
    }

    if (target == null) {
      throw StateError('No suitable address found');
    }

    return RingBasedServerSocket.bind(ring, target, port, backlog);
  }
}
