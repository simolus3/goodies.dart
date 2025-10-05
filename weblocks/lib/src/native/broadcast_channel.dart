import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../interface.dart';
import 'bindings.dart';
import 'implementation.dart';

final class NativeBroadcastChannel extends Stream<String>
    implements Finalizable, BroadcastChannel {
  @override
  final String name;
  final Pointer<Void> channel;
  final ReceivePort _port;
  late final StreamSubscription<void> _portSubscription;
  final List<MultiStreamController<String>> _listeners = [];

  bool _isClosed = false;

  NativeBroadcastChannel._(this.name, this.channel, this._port) {
    channelFinalizer.attach(this, channel, detach: this);

    // Listen on the port right away to avoid the port buffering messages. This
    // gives us the same semantic as on the web.
    _portSubscription = _port.listen((event) {
      final received = event as String;
      for (final controller in _listeners) {
        controller.add(received);
      }
    });
  }

  factory NativeBroadcastChannel(Pointer<Void> client, String name) {
    final receive = ReceivePort('Receive for broadcast channel $name');

    return using((alloc) {
      final encodedName = utf8.encode(name);
      final bytes = alloc.allocBytes(encodedName);

      final channel = pkg_weblocks_broadcast_channel_new(
        encodedName.length,
        bytes,
        client,
        receive.sendPort.nativePort,
      );
      return NativeBroadcastChannel._(name, channel, receive);
    });
  }

  void _checkNotClosed() {
    if (_isClosed) {
      throw StateError('This BroadcastChannel has already been closed.');
    }
  }

  @override
  StreamSubscription<String> listen(
    void Function(String event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _checkNotClosed();
    return Stream<String>.multi((controller) {
      _listeners.add(controller);
      controller.onCancel = () => _listeners.remove(controller);
    }).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  void send(String message) {
    _checkNotClosed();

    final native = message.toNativeUtf8(allocator: malloc);
    pkg_weblocks_broadcast_channel_send(channel, native.cast());
    malloc.free(native);
  }

  @override
  void close() {
    if (!_isClosed) {
      _isClosed = true;
      _port.close();
      _portSubscription.cancel();
      for (final listener in _listeners) {
        listener.close();
      }

      channelFinalizer.detach(this);
      pkg_weblocks_broadcast_channel_free(channel);
    }
  }
}
