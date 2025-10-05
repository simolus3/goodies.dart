import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;
import 'interface.dart';

final LockManager lockManagerImpl = WebLockManager(_navigator.locks);

@JS('navigator')
external web.Navigator get _navigator;

final class WebLockManager implements LockManager {
  final web.LockManager _implementation;

  WebLockManager(this._implementation);

  @override
  Future<LockManagerSnapshot> query() async {
    final snapshot = await _implementation.query().toDart;

    return LockManagerSnapshot(
      pending: snapshot.pending.toDart.map((e) => e.asLockInfo).toList(),
      held: snapshot.held.toDart.map((e) => e.asLockInfo).toList(),
    );
  }

  @override
  LockRequest request(
    String name, {
    bool exclusive = true,
    bool ifAvailable = false,
    bool steal = false,
  }) {
    final canAbort = !steal && !ifAvailable;
    final abort = canAbort ? web.AbortController() : null;
    final state = _WebLockRequestState(
      exclusive: exclusive,
      name: name,
      abortController: abort,
    );

    JSPromise<JSAny?> callback(web.Lock? lock) {
      final didGrant = lock != null;
      if (!state._didAcquire.isCompleted) {
        state._didAcquire.complete(didGrant);
      }

      if (didGrant) {
        return state._release.future.toJS;
      } else {
        return Future.value().toJS;
      }
    }

    final completion = _implementation.request(
      name,
      abort != null
          ? web.LockOptions(
              mode: exclusive ? 'exclusive' : 'shared',
              ifAvailable: ifAvailable,
              steal: steal,
              signal: abort.signal,
            )
          : web.LockOptions(
              mode: exclusive ? 'exclusive' : 'shared',
              ifAvailable: ifAvailable,
              steal: steal,
            ),
      callback.toJS,
    );

    completion.toDart.onError<web.DOMException>((e, s) {
      if (state._didAcquire.isCompleted) {
        if (e.code == web.DOMException.ABORT_ERR) {
          // Stolen by another request.
          state._stolen.complete();
          if (!state._release.isCompleted) {
            state._release.complete();
          }
        }
      } else {
        // Failed to acquire lock.
        state._didAcquire.completeError(e, s);
      }

      return null;
    });

    return _LockRequest(state);
  }

  @override
  BroadcastChannel broadcastChannel(String name) {
    return _WebBroadcastChannel(web.BroadcastChannel(name));
  }
}

extension on web.LockInfo {
  LockInfo get asLockInfo {
    return LockInfo(
      name: name,
      exclusive: mode == 'exclusive',
      clientId: clientId,
    );
  }
}

final class _WebLockRequestState implements LockDescription {
  @override
  final bool exclusive;

  @override
  final String name;

  final web.AbortController? abortController;

  final Completer<bool> _didAcquire = Completer();
  final Completer<void> _release = Completer();
  final Completer<void> _stolen = Completer();

  _WebLockRequestState({
    required this.abortController,
    required this.exclusive,
    required this.name,
  });
}

final class _LockRequest implements LockRequest {
  final _WebLockRequestState _state;
  final _HeldLock _asHeld;

  _LockRequest(this._state) : _asHeld = _HeldLock(_state);

  @override
  bool get exclusive => _state.exclusive;

  @override
  String get name => _state.name;

  @override
  void cancel() {
    if (_state._didAcquire.isCompleted) {
      throw StateError(
        "Can't cancel request, the lock has already been granted",
      );
    }

    if (_state.abortController == null) {
      throw StateError("Can't cancel requests that have steal or ifAvailable");
    }

    if (!_state._release.isCompleted) {
      _state.abortController?.abort();
      _state._didAcquire.completeError(const LockRequestCancelled());
      _state._release.complete();
    }
  }

  @override
  Future<HeldLock?> get completion {
    return _state._didAcquire.future.then((didAcquire) {
      return didAcquire ? _asHeld : null;
    });
  }
}

final class _HeldLock implements HeldLock {
  final _WebLockRequestState _state;

  _HeldLock(this._state);

  @override
  bool get exclusive => _state.exclusive;

  @override
  String get name => _state.name;

  @override
  bool get isStolen => _state._stolen.isCompleted;

  @override
  Future<void> get stolen => _state._stolen.future;

  @override
  void release() {
    if (!_state._release.isCompleted) {
      _state._release.complete();
    }
  }
}

final class _WebBroadcastChannel extends Stream<String>
    implements BroadcastChannel {
  final web.BroadcastChannel _web;
  final StreamController<String> _controller = StreamController.broadcast();

  bool _isClosed = false;

  _WebBroadcastChannel(this._web) {
    final messages = web.EventStreamProviders.messageEvent
        .forTarget(_web)
        .map((e) => (e.data as JSString).toDart);
    StreamSubscription<String>? sub;

    _controller
      ..onListen = () {
        // Not using addStream because we need to cancel the stream in [close].
        sub = messages.listen(_controller.add);
      }
      ..onCancel = () {
        sub?.cancel();
        sub = null;
      };
  }

  void _checkNotClosed() {
    if (_isClosed) {
      // Browsers also check this, but checking in Dart gives us consistent
      // exceptions across native and web.
      throw StateError('This BroadcastChannel has already been closed.');
    }
  }

  @override
  bool get isBroadcast => true;

  @override
  StreamSubscription<String> listen(
    void Function(String event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _checkNotClosed();
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  String get name => _web.name;

  @override
  void send(String message) {
    _checkNotClosed();
    _web.postMessage(message.toJS);
  }

  @override
  void close() {
    if (!_isClosed) {
      _isClosed = true;
      _web.close();
      _controller.close();
    }
  }
}
