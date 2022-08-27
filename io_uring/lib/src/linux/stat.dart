import 'dart:ffi';

import 'dart:io';

// ignore_for_file: constant_identifier_names, library_private_types_in_public_api, non_constant_identifier_names, camel_case_types

class statx_timestamp extends Struct {
  @Uint64()
  external int tv_sec;
  @Uint32()
  external int tv_nsec;
}

class statx extends Struct {
  @Uint32()
  external int stx_mask;
  @Uint32()
  external int stx_blksize;
  @Uint64()
  external int stx_attributes;
  @Uint32()
  external int stx_nlink;
  @Uint32()
  external int stx_uid;
  @Uint32()
  external int stx_gid;
  @Uint16()
  external int stx_mode;
  @Uint64()
  external int stx_ino;
  @Uint64()
  external int stx_size;
  @Uint64()
  external int stx_blocks;
  @Uint64()
  external int stx_attributes_mask;
  external statx_timestamp stx_atime; // Last accesss
  external statx_timestamp stx_btime; // Creation
  external statx_timestamp stx_ctime; // Last status change
  external statx_timestamp stx_mtime; // Last modification
  @Uint32()
  external int stx_rdev_major;
  @Uint32()
  external int stx_rdev_minor;
  @Uint32()
  external int stx_dev_major;
  @Uint32()
  external int stx_dev_minor;
  @Uint64()
  external int stx_mnt_id;
}

// size of the `statx` in the Kernel, in bytes
const int sizeofStatx = 256;

class IoUringFileStat implements FileStat {
  @override
  final DateTime changed;

  @override
  final DateTime modified;

  @override
  final DateTime accessed;

  @override
  final FileSystemEntityType type;

  /// The mode of the file system object.
  ///
  /// Permissions are encoded in the lower 16 bits of this number, and can be
  /// decoded using the [modeString] getter.
  @override
  final int mode;

  @override
  final int size;

  IoUringFileStat(this.changed, this.modified, this.accessed, this.type,
      this.mode, this.size);

  IoUringFileStat.notFound()
      : changed = DateTime(0),
        modified = DateTime(0),
        accessed = DateTime(0),
        type = FileSystemEntityType.notFound,
        mode = 0,
        size = 0;

  @override
  String toString() => """
FileStat: type $type
          changed $changed
          modified $modified
          accessed $accessed
          mode ${modeString()}
          size $size""";

  @override
  String modeString() {
    final permissions = mode & 0xFFF;
    const codes = ['---', '--x', '-w-', '-wx', 'r--', 'r-x', 'rw-', 'rwx'];
    final result = <String>[];
    if ((permissions & 0x800) != 0) result.add("(suid) ");
    if ((permissions & 0x400) != 0) result.add("(guid) ");
    if ((permissions & 0x200) != 0) result.add("(sticky) ");
    result
      ..add(codes[(permissions >> 6) & 0x7])
      ..add(codes[(permissions >> 3) & 0x7])
      ..add(codes[permissions & 0x7]);
    return result.join();
  }
}

extension on statx_timestamp {
  DateTime toDateTime() {
    const secondsToMicro = 1000000; // 10⁶
    const microToNano = 1000;

    return DateTime.fromMicrosecondsSinceEpoch(
        tv_sec * secondsToMicro + tv_nsec ~/ microToNano);
  }
}

extension StatToDart on statx {
  FileStat toFileStat() {
    final fileType = stx_mode & _fileType;
    FileSystemEntityType dartType;
    switch (fileType) {
      case _reg:
        dartType = FileSystemEntityType.file;
        break;
      case _dir:
        dartType = FileSystemEntityType.directory;
        break;
      case _link:
        dartType = FileSystemEntityType.link;
        break;
      default:
        dartType = FileSystemEntityType.notFound;
    }

    return IoUringFileStat(
      stx_ctime.toDateTime(),
      stx_mtime.toDateTime(),
      stx_atime.toDateTime(),
      dartType,
      stx_mode & 0xFFF,
      stx_size,
    );
  }
}

const _fileType = 0xF000;
const _reg = 0x8000;
const _dir = 0x4000;
const _link = 0xA000;
