/// @docImport 'dart:isolate';
library;

abstract interface class LockManager {
  LockRequest request(
    String name, {
    bool exclusive = true,
    bool ifAvailable = false,
    bool steal = false,
  });

  Future<LockManagerSnapshot> query();
}

final class LockManagerSnapshot {
  final List<SnapshotEntry> pending;
  final List<SnapshotEntry> held;

  LockManagerSnapshot({required this.pending, required this.held});
}

typedef SnapshotEntry = ({String name, bool exclusive, String clientId});

abstract interface class LockDescription {
  String get name;
  bool get exclusive;
}

abstract interface class LockInfo extends LockDescription {
  /// The client id currently operating on the lock. This is an opaque name on
  /// the web, and the [Isolate.debugName] of the isolate attempting to obtain
  /// the lock on native platforms.
  String get clientId;
}

abstract interface class LockRequest extends LockDescription {
  Future<HeldLock?> get completion;

  void cancel();
}

abstract interface class HeldLock extends LockDescription {
  Future<void> get stolen;
  bool get isStolen;

  void release();
}

final class LockRequestCancelled implements Exception {
  @override
  String toString() {
    return 'Lock request was cancelled';
  }
}
