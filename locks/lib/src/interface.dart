/// @docImport 'dart:isolate';
/// @docImport 'package:locks/locks.dart';
library;

/// An instance managing access to a group of locks.
///
/// The locks managed by a manager are shared between isolates or tabs without
/// requiring this object to be sent through ports.
///
/// To obtain an instance of this class, use [lockManager].
abstract interface class LockManager {
  LockRequest request(
    String name, {
    bool exclusive = true,
    bool ifAvailable = false,
    bool steal = false,
  });

  /// Returns a [LockManagerSnapshot] describing pending and held lock requests
  /// on this manager.
  Future<LockManagerSnapshot> query();
}

/// A consistent snapshot of all requests being active at a point in time.
final class LockManagerSnapshot {
  /// All requests that are currently pending (haven't been granted or
  /// [LockRequest.cancel]ed) yet.
  final List<LockInfo> pending;

  /// All requests that are currently being held.
  final List<LockInfo> held;

  /// Creates a snapshot of the [pending] and [held] lists.
  LockManagerSnapshot({required this.pending, required this.held});

  @override
  String toString() {
    return 'Pending: $pending, held: $held';
  }
}

/// Parent interface for lock requests
abstract interface class LockDescription {
  /// The name of the lock being requested.
  String get name;

  /// Whether the request is exclusive.
  ///
  /// If false, this and other non-exclusive requests can hold the lock at the
  /// same time.
  bool get exclusive;
}

/// A request to a lock.
///
/// This consists of the name identifying the lock, whether the request is
/// exclusive and an opaque client id.
final class LockInfo implements LockDescription {
  /// The client id currently operating on the lock. This is an opaque name on
  /// the web, and the [Isolate.debugName] of the isolate attempting to obtain
  /// the lock on native platforms.
  ///
  /// Note that the same client ids can appear multiple times in
  /// [LockManagerSnapshot] because locks are asynchronous and a single thread
  /// can hold multiple locks.
  final String clientId;

  @override
  final bool exclusive;

  @override
  final String name;

  /// Creates a [LockInfo] description from its fields.
  const LockInfo({
    required this.clientId,
    required this.exclusive,
    required this.name,
  });
}

/// A pending request to a lock.
///
/// The request completes via the [completion] future.
abstract interface class LockRequest extends LockDescription {
  Future<HeldLock?> get completion;

  /// Cancels this request.
  ///
  /// This will make [completion] complete with a [LockRequestCancelled]
  /// exception.
  ///
  /// It is illegal to cancel locks requested with `ifAvailable: true` or with
  /// `steal: true`. To cancel those, await [completion] and immediately call
  /// [HeldLock.release].
  void cancel();
}

/// A lock currently being held (until [release] is called).
abstract interface class HeldLock extends LockDescription {
  /// A future that completes once this lock gets stolen by another request.
  ///
  /// See [isStolen] for the current state.
  Future<void> get stolen;

  /// Whether the lock has been stolen by another request (via `isStolen: true`
  /// in [LockManager.request]).
  ///
  /// For a future that completes once this request is stolen, see [stolen].
  bool get isStolen;

  /// Releases the lock, allowing another request to progress.
  ///
  /// Both on the web and on native platforms, locks are automatically released
  /// when the owning isolate or tab is closed.
  ///
  /// On native platforms only, locks are also released if the [HeldLock] and
  /// [LockRequest] instances become unreachable by other means. However, it is
  /// recommended to always call [release] explicitly for web compatibility.
  void release();
}

/// An exception thrown by [LockRequest.completion] when the request is
/// cancelled.
final class LockRequestCancelled implements Exception {
  const LockRequestCancelled();

  @override
  String toString() {
    return 'Lock request was cancelled';
  }
}
