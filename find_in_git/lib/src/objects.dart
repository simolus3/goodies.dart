import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:charcode/ascii.dart';
import 'package:crypto/crypto.dart';

import 'object_id.dart';

abstract class GitObject {
  ObjectId get id;

  static Future<GitObject?> decodeObjectFile(
      ObjectId ownId, Stream<List<int>> contents) async {
    final uncompressed = contents.transform(ZLibDecoder());
    final reader = _ObjectParser(uncompressed);

    try {
      return await reader.read(ownId);
    } on _CouldNotParseObjectException {
      return null;
    } finally {
      await reader.close();
    }
  }
}

class Commit extends GitObject {
  @override
  final ObjectId id;
  final ObjectId treeId;

  Commit(this.id, this.treeId);

  @override
  String toString() {
    return 'Commit $id, tree $treeId';
  }
}

class Tree extends GitObject {
  @override
  final ObjectId id;
  final List<TreeEntry> entries;

  Tree(this.id, this.entries) {
    for (final entry in entries) {
      entry.tree = this;
    }
  }

  @override
  String toString() {
    final buffer = StringBuffer('Tree $id\n');
    for (final entry in entries) {
      buffer
        ..write(entry.mode.toString().padLeft(6, '0'))
        ..write(' ')
        ..write(entry.reference)
        ..write(' ')
        ..writeln(entry.name);
    }

    return buffer.toString();
  }
}

class TreeEntry {
  late Tree tree;

  final int mode;
  final String name;
  final ObjectId reference;

  TreeEntry(this.mode, this.name, this.reference);
}

class Blob extends GitObject {
  @override
  final ObjectId id;

  Blob(this.id);
}

class _ObjectParser {
  final ChunkedStreamReader<int> _source;

  _ObjectParser(Stream<List<int>> source)
      : _source = ChunkedStreamReader(source);

  Future<Uint8List> _readBytes(int amount) async {
    final result = BytesBuilder();

    final actuallyRead = await _source.readBytes(amount);
    result.add(actuallyRead);

    if (actuallyRead.length != amount) {
      throw _CouldNotParseObjectException('Unexpected end of file');
    }

    return result.takeBytes();
  }

  Future<String> _read(int amount) async {
    return utf8.decode(await _readBytes(amount));
  }

  Future<void> _expectString(String constant) async {
    if (await _read(constant.length) != constant) {
      throw _CouldNotParseObjectException('Expected "$constant"');
    }
  }

  Future<void> _skip(int amount) => _read(amount);

  Future<int> _charCode() async {
    return (await _read(1)).codeUnitAt(0);
  }

  Future<String> _readTerminatedString({int terminator = 0}) async {
    final buffer = StringBuffer();
    int char;
    while ((char = await _charCode()) != terminator) {
      buffer.writeCharCode(char);
    }

    return buffer.toString();
  }

  Future<void> close() => _source.cancel();

  Future<GitObject> read(ObjectId ownId) async {
    final char = await _charCode();
    switch (char) {
      case $b: // blob
        await _expectString('lob ');
        return Blob(ownId);
      case $c: // commit
        await _expectString('ommit ');
        await _skip(5); // length plus space
        await _expectString('tree ');

        final tree = ObjectId.hex(await _read(40));
        return Commit(ownId, tree);
      case $t: // tree
        await _expectString('ree ');
        var remaining = int.parse(await _readTerminatedString());
        final entries = <TreeEntry>[];

        Future<void> readEntry() async {
          final modeStr = await _readTerminatedString(terminator: $space);
          final mode = int.parse(modeStr);
          final fileName = await _readTerminatedString();
          final treeOrBlobId = ObjectId(Digest(await _readBytes(20)));

          entries.add(TreeEntry(mode, fileName, treeOrBlobId));
          remaining -= modeStr.length + fileName.length + 22;
        }

        while (remaining > 0) {
          await readEntry();
        }

        return Tree(ownId, entries);
      default:
        throw _CouldNotParseObjectException('Unexpected object kind');
    }
  }
}

class _CouldNotParseObjectException implements Exception {
  final String message;

  _CouldNotParseObjectException(this.message);

  @override
  String toString() {
    return 'Could not parse git object: $message';
  }
}
