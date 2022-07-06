import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';

import '../object_id.dart';
import '../objects.dart';
import 'repository.dart';

class FileRepository extends GitRepository {
  final Directory directory;

  final Directory _gitDirectory;

  FileRepository(this.directory)
      : _gitDirectory = directory.childDirectory('.git');

  @override
  Stream<ObjectId> get commits {
    return Stream.fromFuture(Process.start('git', ['rev-list', '--branches']))
        .asyncExpand((process) {
      final lines =
          process.stdout.map(utf8.decode).transform(const LineSplitter());
      return lines.map(ObjectId.hex);
    });
  }

  @override
  Future<GitObject?> read(ObjectId id) {
    final hex = id.toString();

    final file = _gitDirectory
        .childDirectory('objects')
        .childDirectory(hex.substring(0, 2))
        .childFile(hex.substring(2));

    return GitObject.decodeObjectFile(id, file.openRead());
  }
}
