import 'dart:io';

import '../../io_uring.dart';
import '../io_uring.dart';
import 'file_system_entity.dart';
import 'socket.dart';

T runWithIOUring<T>(T Function() body, IOUring uring) {
  final impl = uring as IOUringImpl;

  return IOOverrides.runZoned(
    body,
    stat: (path) => impl.run(impl.stat(path)),
    statSync: (path) => impl.runSync(impl.stat(path)),
    fseGetType: (path, followLinks) =>
        impl.run(impl.stat(path, followLinks: false)).then((stat) => stat.type),
    fseGetTypeSync: (path, followLinks) =>
        impl.runSync(impl.stat(path, followLinks: false)).type,
    createDirectory:
        impl.escaped1((path) => wrapDirectory(impl, Directory(path))),
    createFile: impl.escaped1((path) => wrapFile(impl, File(path))),
    createLink: impl.escaped1((path) => wrapLink(impl, Link(path))),
    fsWatch: (String path, int events, bool recursive) {
      throw UnimplementedError();
    },
    fsWatchIsSupported: () => true,
    socketConnect: (dynamic host, int port,
        {dynamic sourceAddress, Duration? timeout}) {
      return RingBasedSocket.startConnect(impl, host, port,
              sourceAddress: sourceAddress, timeout: timeout)
          .then((task) => task.socket);
    },
    socketStartConnect: (dynamic host, int port,
        {dynamic sourceAddress, Duration? timeout}) {
      return RingBasedSocket.startConnect(impl, host, port,
          sourceAddress: sourceAddress, timeout: timeout);
    },
  );
}
