import 'dart:io';

/// A file system watcher.
///
/// Similar to Dart, we use `inotify` to receive for file system event. However,
/// we use `io_uring` to get notified when a watch set is changed.
class RingBasedFileSystemWatcher {
  Stream<FileSystemEvent> eventsFor(String path, int events, bool recursive) {}
}
