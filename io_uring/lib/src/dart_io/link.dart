import 'dart:io';

import '../io_uring.dart';

import 'file_system_entity.dart';

class RingBasedLink extends RingBasedFileSystemEntity implements Link {
  @override
  final Link inner;

  @override
  final IOUringImpl ring;

  RingBasedLink(this.inner, this.ring);

  RingBasedLink _wrap(Link inner) => RingBasedLink(inner, ring);

  @override
  Link get absolute => RingBasedLink(inner.absolute, ring);

  @override
  Future<Link> create(String target, {bool recursive = false}) {
    // todo: We can implement this with Linux 5.15
    return inner.create(target, recursive: recursive).then(_wrap);
  }

  @override
  void createSync(String target, {bool recursive = false}) {
    inner.createSync(target, recursive: recursive);
  }

  @override
  Future<String> target() {
    return inner.target();
  }

  @override
  String targetSync() {
    return inner.targetSync();
  }

  @override
  FileSystemEntityType get type => FileSystemEntityType.link;

  @override
  Future<Link> update(String target) {
    return inner.update(target).then(_wrap);
  }

  @override
  void updateSync(String target) {
    inner.updateSync(target);
  }

  @override
  Future<Link> rename(String newPath) {
    // Note that creating a File(path) will automatically create a RingBasedLink
    // due to overrides.
    return ring.run(ring.renameat2(path, newPath)).then((_) => Link(newPath));
  }

  @override
  Link renameSync(String newPath) {
    ring.runSync(ring.renameat2(path, newPath));
    return Link(newPath);
  }
}
