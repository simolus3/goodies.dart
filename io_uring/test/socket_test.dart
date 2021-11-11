import 'dart:async';
import 'dart:io';

import 'package:io_uring/io_uring.dart';
import 'package:test/test.dart';

void main() {
  late IOUring ring;

  setUp(() async {
    ring = await IOUring.initialize();
  });
  tearDown(() {
    print('dispose');
    return ring.dispose();
  });

  group('server sockets', () {
    test('can accept new sockets', () async {
      var amountOfSockets = 0;
      var amountOfBytesReceived = 0;
      final portCompleter = Completer<int>();
      final shutdownCompleter = Completer<void>();
      final shutdownDoneCompleter = Completer<void>();

      // ignore: unawaited_futures
      runWithIOUring(() async {
        final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
        portCompleter.complete(server.port);

        final connections = <Socket>[];

        server.listen((socket) {
          amountOfSockets++;
          connections.add(socket);

          socket.listen((event) => amountOfBytesReceived += event.length);
        });

        await shutdownCompleter.future.then((_) => server.close());

        for (final socket in connections) {
          socket.destroy();
        }

        shutdownDoneCompleter.complete();
      }, ring);

      final port = await portCompleter.future;

      Future<void> connect() async {
        final socket = await Socket.connect(InternetAddress.anyIPv4, port);
        socket.add([1, 2, 3]);
        await socket.flush();
        await socket.close();
      }

      await Future.wait([connect(), connect(), connect()]);

      shutdownCompleter.complete();
      await shutdownDoneCompleter.future;

      expect(amountOfSockets, 3);
      expect(amountOfBytesReceived, 9);
      print('done');
    });
  });
}
