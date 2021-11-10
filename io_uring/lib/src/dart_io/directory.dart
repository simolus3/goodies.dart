import 'dart:io';

import '../io_uring.dart';
import 'file_system_entity.dart';

class RingBasedDirectory extends RingBasedFileSystemEntity
    implements Directory {
  @override
  final IOUringImpl ring;
  @override
  final Directory inner;

  RingBasedDirectory(this.ring, this.inner);

  RingBasedDirectory _wrapDir(Directory dir) => wrapDirectory(ring, dir);

  @override
  Directory get absolute => wrapDirectory(ring, inner.absolute);

  @override
  Future<Directory> create({bool recursive = false}) {
    // todo: We will be able to asyncify this in Linux 5.15
    return inner.create(recursive: recursive).then(_wrapDir);
  }

  @override
  void createSync({bool recursive = false}) {
    inner.createSync(recursive: true);
  }

  @override
  Future<Directory> createTemp([String? prefix]) {
    return inner.createTemp(prefix).then(_wrapDir);
  }

  @override
  Directory createTempSync([String? prefix]) {
    return _wrapDir(inner.createTempSync(prefix));
  }

  @override
  Stream<FileSystemEntity> list(
      {bool recursive = false, bool followLinks = true}) {
    return inner
        .list(recursive: recursive, followLinks: followLinks)
        .map((e) => wrap(ring, e));
  }

  @override
  List<FileSystemEntity> listSync(
      {bool recursive = false, bool followLinks = true}) {
    return [
      for (final entity
          in inner.listSync(recursive: recursive, followLinks: followLinks))
        wrap(ring, entity)
    ];
  }

  @override
  Future<Directory> rename(String newPath) {
    return inner.rename(newPath).then(_wrapDir);
  }

  @override
  Directory renameSync(String newPath) {
    return _wrapDir(inner.renameSync(newPath));
  }

  @override
  FileSystemEntityType get type => FileSystemEntityType.directory;
}
