library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../interface.dart';
import 'bindings.dart';

final class NativeLockManager implements LockManager, Finalizable {
  final Pointer<Void> _client;

  NativeLockManager._(this._client) {
    clientFinalizer.attach(this, _client);
  }

  factory NativeLockManager(String clientName) {
    final encoded = utf8.encode(clientName);
    return using((alloc) {
      final client = pkg_locks_client(
        encoded.length,
        alloc.allocBytes(encoded),
        NativeApi.initializeApiDLData,
      );
      return NativeLockManager._(client);
    });
  }

  static NativeLockManager forCurrentIsolate() {
    final current = Isolate.current;
    return NativeLockManager(
      current.debugName ??
          '<unnamed isolate: ${identityHashCode(current.controlPort)}>',
    );
  }

  @override
  LockRequest request(
    String name, {
    bool exclusive = true,
    bool ifAvailable = false,
    bool steal = false,
  }) {
    // Prevent things forbidden on the web for consistency
    if (name.startsWith('-')) {
      throw ArgumentError.value(name, 'name', 'Must not start with a hyphen');
    }
    if (steal && (!exclusive || ifAvailable)) {
      throw ArgumentError.value(
        'When steal is enable, exclusive must also be true and ifAvailable must be disabled.',
      );
    }

    final port = ReceivePort('obtaining lock $name');
    final encoded = utf8.encode(name);

    var flags = 0;
    if (!exclusive) {
      flags |= FLAG_SHARED;
    }
    if (ifAvailable) {
      flags |= FLAG_IF_AVAILABLE;
    }
    if (steal) {
      flags |= FLAG_STEAL;
    }

    final request = using((alloc) {
      return pkg_locks_obtain(
        encoded.length,
        alloc.allocBytes(encoded),
        _client,
        flags,
        port.sendPort.nativePort,
      );
    });

    final internalRequest = _InternalLockRequest(
      request: request,
      name: name,
      exclusive: exclusive,
      port: port,
    );
    return _NativeLockRequest(internalRequest, ifAvailable || steal);
  }

  @override
  Future<LockManagerSnapshot> query() async {
    final port = ReceivePort('LockManager.query()');
    pkg_locks_snapshot(port.sendPort.nativePort);

    final msg = (await port.first) as List;
    final held = <LockInfo>[];
    final pending = <LockInfo>[];

    for (var i = 0; i < msg.length; i += 4) {
      final name = msg[i] as String;
      final clientId = msg[i + 1] as String;
      final exclusive = msg[i + 2] as bool;
      final isHeld = msg[i + 3] as bool;

      (isHeld ? held : pending).add(
        LockInfo(name: name, clientId: clientId, exclusive: exclusive),
      );
    }

    return LockManagerSnapshot(pending: pending, held: held);
  }
}

final class _InternalLockRequest implements Finalizable {
  final Pointer<Void> request;
  final String name;
  final bool exclusive;

  final Completer<void> _granted = Completer();
  final Completer<void> _stolen = Completer();

  var closed = false;
  var wasUnavailable = false;
  StreamSubscription? receivePortSubscription;

  _InternalLockRequest({
    required this.request,
    required this.name,
    required this.exclusive,
    required ReceivePort port,
  }) {
    requestFinalizer.attach(this, request, detach: this);

    receivePortSubscription = port.listen((msg) {
      switch (msg[0] as String) {
        case 'stolen':
          _stolen.complete();
          close();
        case 'unavailable':
          wasUnavailable = true;
          _granted.complete();
          close();
        case 'locked':
          _granted.complete();
        default:
          throw StateError('unknown message from native implementation: $msg');
      }
    });
  }

  void close() {
    if (!closed) {
      closed = true;
      requestFinalizer.detach(this);
      pkg_locks_unlock(request);
      receivePortSubscription?.cancel();
    }
  }
}

final class _NativeLockRequest implements LockRequest {
  final _InternalLockRequest _request;
  final bool isIfAvailableOrSteal;

  _NativeLockRequest(this._request, this.isIfAvailableOrSteal);

  @override
  void cancel() {
    if (isIfAvailableOrSteal) {
      throw StateError('Cannot cancel steal or ifAvailable requests');
    }
    if (_request._granted.isCompleted) {
      throw StateError('Cannot cancel requests that have already been granted');
    }

    if (!_request._granted.isCompleted) {
      _request._granted.completeError(const LockRequestCancelled());
    }

    _request.close();
  }

  @override
  Future<HeldLock?> get completion async {
    await _request._granted.future;
    return _request.wasUnavailable ? null : _NativeHeldLock(_request);
  }

  @override
  bool get exclusive => _request.exclusive;

  @override
  String get name => _request.name;
}

final class _NativeHeldLock implements HeldLock {
  final _InternalLockRequest _request;

  _NativeHeldLock(this._request);

  @override
  Future<void> get stolen => _request._stolen.future;

  @override
  bool get isStolen => _request._stolen.isCompleted;

  @override
  bool get exclusive => _request.exclusive;

  @override
  String get name => _request.name;

  @override
  void release() {
    _request.close();
  }
}

extension on Allocator {
  Pointer<Uint8> allocBytes(Uint8List data) {
    final buffer = this<Uint8>(data.length);
    buffer.asTypedList(data.length).setAll(0, data);
    return buffer;
  }
}
