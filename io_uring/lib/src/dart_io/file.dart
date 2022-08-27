import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../buffers.dart';
import '../io_uring.dart';
import '../linux/errors.dart';
import '../linux/file.dart';
import '../utils.dart';
import 'file_system_entity.dart';

class RingBasedFile extends RingBasedFileSystemEntity implements File {
  @override
  final IOUringImpl ring;
  @override
  final File inner;

  RingBasedFile(this.ring, this.inner);

  RingBasedFile _wrapFile(File inner) => RingBasedFile(ring, inner);

  @override
  File get absolute => _wrapFile(inner.absolute);

  @override
  Future<File> copy(String newPath) {
    // todo: Implement copy using splice?
    return inner.copy(newPath).then(_wrapFile);
  }

  @override
  File copySync(String newPath) {
    return _wrapFile(inner.copySync(newPath));
  }

  @override
  Future<File> create({bool recursive = false}) async {
    if (recursive && !await parent.exists()) {
      await parent.create(recursive: true);
    }

    final fd = await ring.run(ring.openAt2(path, flags: O_CREAT, mode: 0x1ff));
    await ring.run(ring.close(fd, path));
    return this;
  }

  @override
  void createSync({bool recursive = false}) {
    if (recursive && !parent.existsSync()) {
      parent.create(recursive: true);
    }

    final fd = ring.runSync(ring.openAt2(path, flags: O_CREAT, mode: 0x1ff));
    ring.runSync(ring.close(fd, path));
  }

  Future<FileStat> _statAndCheckFile() {
    return this.stat().then((stat) {
      if (stat.type != FileSystemEntityType.file) {
        throw FileSystemException('Not a file!', path);
      }

      return stat;
    });
  }

  FileStat _statAndCheckFileSync() {
    final stat = this.statSync();
    if (stat.type != FileSystemEntityType.file) {
      throw FileSystemException('Not a file!', path);
    }

    return stat;
  }

  @override
  Future<DateTime> lastAccessed() {
    return _statAndCheckFile().then((stat) => stat.accessed);
  }

  @override
  DateTime lastAccessedSync() {
    return _statAndCheckFileSync().accessed;
  }

  @override
  Future<DateTime> lastModified() {
    return _statAndCheckFile().then((stat) => stat.modified);
  }

  @override
  DateTime lastModifiedSync() {
    return _statAndCheckFileSync().modified;
  }

  @override
  Future<int> length() {
    return _statAndCheckFile().then((stat) => stat.size);
  }

  @override
  int lengthSync() {
    return _statAndCheckFileSync().size;
  }

  Operation<int> _open(FileMode mode) {
    int flags;
    switch (mode) {
      case FileMode.append:
        flags = O_CREAT | O_RDWR | O_APPEND;
        break;
      case FileMode.read:
        flags = O_RDONLY;
        break;
      case FileMode.write:
        flags = O_CREAT | O_RDWR;
        break;
      case FileMode.writeOnly:
        flags = O_CREAT | O_WRONLY;
        break;
      case FileMode.writeOnlyAppend:
        flags = O_CREAT | O_WRONLY | O_APPEND;
        break;
      default:
        throw AssertionError('unreachable');
    }

    final int creationMode;
    if (flags & O_CREAT == 0) {
      // We'll get an invalid argument error from the Kernel if we set a mode
      // without the O_CREATE flag active.
      creationMode = 0;
    } else {
      // This mode will be ANDed onto the default mode, and we want to keep
      // the default file mode.
      creationMode = 0x1ff;
    }

    return ring.openAt2(path, flags: flags, mode: creationMode);
  }

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) {
    return _openFile(mode: mode);
  }

  Future<_OpenedFile> _openFile({FileMode mode = FileMode.read}) {
    return ring.run(_open(mode)).then((fd) => _OpenedFile(ring, this, fd));
  }

  @override
  Stream<List<int>> openRead([int? start, int? end]) {
    if (start != null && start == end) {
      return const Stream.empty();
    }

    // We can make this controller sync because we'll only ever add events
    // in response to other async happenings.
    final controller = StreamController<List<int>>(sync: true);

    _OpenedFile? file;
    final remaining = end == null ? null : end - (start ?? 0);

    controller
      ..onListen = () {
        _openFile(mode: FileMode.read).then<_OpenedFile>((file) {
          if (start != null) {
            return file.setPosition(start);
          } else {
            return file;
          }
        }).then((openedFile) {
          file = openedFile;

          controller
              .addStream(ReadFromFdStream(ring, openedFile.fd,
                  path: path, bytesToRead: remaining))
              .then((void _) {
            file?.close();
            controller.close();
          });
        }, onError: (Object e, StackTrace s) {
          controller
            ..addError(e, s)
            ..close();
        });
      }
      ..onCancel = () {
        file?.close();
      };

    return controller.stream;
  }

  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) {
    final fd = ring.runSync(_open(mode));
    return _OpenedFile(ring, this, fd);
  }

  @override
  IOSink openWrite({FileMode mode = FileMode.write, Encoding encoding = utf8}) {
    final file = _openFile(mode: mode);

    final buffer = ring.buffers.useBuffer();
    final StreamConsumer<List<int>> consumer;
    if (buffer != null) {
      consumer = _SharedMemoryFileWriter(ring.buffers, file, buffer);
    } else {
      consumer = _RegularFileWriter(file);
    }

    return IOSink(consumer);
  }

  @override
  Future<Uint8List> readAsBytes() async {
    final buffer = Uint8List(await length());

    final opened = await open(mode: FileMode.read);
    await opened.readInto(buffer);

    return buffer;
  }

  @override
  Uint8List readAsBytesSync() {
    final buffer = Uint8List(lengthSync());

    final opened = openSync(mode: FileMode.read);
    opened.readIntoSync(buffer);

    return buffer;
  }

  @override
  Future<List<String>> readAsLines({Encoding encoding = utf8}) {
    return readAsString(encoding: encoding)
        .then((content) => const LineSplitter().convert(content));
  }

  @override
  List<String> readAsLinesSync({Encoding encoding = utf8}) {
    return inner.readAsLinesSync(encoding: encoding);
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) {
    return readAsBytes().then(encoding.decode);
  }

  @override
  String readAsStringSync({Encoding encoding = utf8}) {
    return encoding.decode(readAsBytesSync());
  }

  @override
  Future<void> setLastAccessed(DateTime time) {
    return inner.setLastAccessed(time);
  }

  @override
  void setLastAccessedSync(DateTime time) {
    inner.setLastAccessedSync(time);
  }

  @override
  Future<void> setLastModified(DateTime time) {
    return inner.setLastModified(time);
  }

  @override
  void setLastModifiedSync(DateTime time) {
    inner.setLastModifiedSync(time);
  }

  @override
  FileSystemEntityType get type => FileSystemEntityType.file;

  @override
  Future<File> writeAsBytes(List<int> bytes,
      {FileMode mode = FileMode.write, bool flush = false}) async {
    final opened = await open(mode: mode);
    await opened.writeFrom(bytes);
    if (flush) await opened.flush();

    return this;
  }

  @override
  void writeAsBytesSync(List<int> bytes,
      {FileMode mode = FileMode.write, bool flush = false}) {
    final opened = openSync(mode: mode);
    opened.writeFromSync(bytes);
    if (flush) opened.flushSync();
  }

  @override
  Future<File> writeAsString(String contents,
      {FileMode mode = FileMode.write,
      Encoding encoding = utf8,
      bool flush = false}) {
    return writeAsBytes(encoding.encode(contents), mode: mode, flush: flush);
  }

  @override
  void writeAsStringSync(String contents,
      {FileMode mode = FileMode.write,
      Encoding encoding = utf8,
      bool flush = false}) {
    inner.writeAsStringSync(contents,
        mode: mode, encoding: encoding, flush: flush);
  }

  @override
  Future<File> rename(String newPath) {
    // Note that creating a File(path) will automatically create a RingBasedFile
    // due to overrides.
    return ring.run(ring.renameat2(path, newPath)).then((_) => File(newPath));
  }

  @override
  File renameSync(String newPath) {
    ring.runSync(ring.renameat2(path, newPath));
    return File(newPath);
  }
}

class _OpenedFile extends RandomAccessFile {
  final IOUringImpl uring;
  final File file;
  final int fd;

  var _isClosed = false;
  var _asyncOperationInProgress = false;

  _OpenedFile(this.uring, this.file, this.fd);

  void _checkCanStart() {
    if (_isClosed) {
      throw StateError('Using RandomAccessFile after calling close');
    }

    if (_asyncOperationInProgress) {
      throw StateError(
          'An async operation is already in progress on this file. '
          'Please await it before starting a new one');
    }
  }

  Future<T> _run<T>(Future<T> future) {
    assert(!_asyncOperationInProgress, 'Had pending operation');
    _asyncOperationInProgress = true;

    return future.whenComplete(() => _asyncOperationInProgress = false);
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;

    _checkCanStart();
    return _run(Future.sync(() async {
      _isClosed = true;
      return uring.run(uring.close(fd, file.path));
    }));
  }

  @override
  void closeSync() {
    _checkCanStart();
    _isClosed = true;
    uring.runSync(uring.close(fd, file.path));
  }

  @override
  Future<RandomAccessFile> flush() {
    _checkCanStart();
    return _run(uring
        .run(uring.fsync(fd, file.path))
        .onError<FileSystemException>((error, _) {},
            test: (error) => error.osError?.errorCode == EINVAL)
        .then((_) => this));
  }

  @override
  void flushSync() {
    _checkCanStart();
    try {
      return uring.runSync(uring.fsync(fd, file.path));
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == EINVAL) {
        // Some special files don't support fsync, ignore
      } else {
        rethrow;
      }
    }
  }

  @override
  Future<int> length() {
    _checkCanStart();
    return Future.value(lengthSync());
  }

  @override
  int lengthSync() {
    _checkCanStart();
    final offset = positionSync();
    final endOffset = uring.binding.dartio_lseek(fd, 0, SEEK_END)
      ..throwIfError(uring.binding);
    uring.binding
        .dartio_lseek(fd, offset, SEEK_SET)
        .throwIfError(uring.binding);

    return endOffset;
  }

  @override
  Future<RandomAccessFile> lock(
      [FileLock mode = FileLock.exclusive, int start = 0, int end = -1]) {
    throw UnimplementedError(
        'lock is not currently implemented under io_uring');
  }

  @override
  void lockSync(
      [FileLock mode = FileLock.exclusive, int start = 0, int end = -1]) {
    throw UnimplementedError(
        'lockSync is not currently implemented under io_uring');
  }

  @override
  String get path => file.path;

  @override
  Future<int> position() {
    _checkCanStart();
    return Future.value(positionSync());
  }

  @override
  int positionSync() {
    _checkCanStart();
    return uring.binding.dartio_lseek(fd, 0, SEEK_CUR)
      ..throwIfError(uring.binding);
  }

  @override
  Future<Uint8List> read(int count) {
    _checkCanStart();
    return _run(Future.sync(() async {
      final buffer = uring.allocator.allocate<Uint8>(count);

      try {
        var totalBytesRead = 0;
        while (totalBytesRead < count) {
          final bytesRead = await uring.run(uring.read(
              fd, buffer.elementAt(totalBytesRead), count - totalBytesRead));
          totalBytesRead += bytesRead;

          if (bytesRead == 0) {
            break; // End of file reached
          }
        }

        final inDartHeap = Uint8List(totalBytesRead);
        inDartHeap.setAll(0, buffer.asTypedList(totalBytesRead));

        return inDartHeap;
      } finally {
        uring.allocator.free(buffer);
      }
    }));
  }

  @override
  Uint8List readSync(int count) {
    _checkCanStart();
    final buffer = uring.allocator.allocate<Uint8>(count);

    try {
      var totalBytesRead = 0;
      while (totalBytesRead < count) {
        final bytesRead = uring.runSync(uring.read(
            fd, buffer.elementAt(totalBytesRead), count - totalBytesRead));
        totalBytesRead += bytesRead;

        if (bytesRead == 0) {
          break; // End of file reached
        }
      }

      final inDartHeap = Uint8List(totalBytesRead);
      inDartHeap.setAll(0, buffer.asTypedList(totalBytesRead));

      return inDartHeap;
    } finally {
      uring.allocator.free(buffer);
    }
  }

  @override
  Future<int> readByte() async {
    final list = await read(1);
    if (list.isEmpty) return -1; // EoF
    return list[0];
  }

  @override
  int readByteSync() {
    final list = readSync(1);
    if (list.isEmpty) return -1; // EoF
    return list[0];
  }

  @override
  Future<int> readInto(List<int> buffer, [int start = 0, int? end]) async {
    RangeError.checkValidRange(start, end, buffer.length);
    final count = (end ?? buffer.length) - start;

    final bytesRead = await read(count);
    buffer.setAll(start, bytesRead);
    return bytesRead.length;
  }

  @override
  int readIntoSync(List<int> buffer, [int start = 0, int? end]) {
    RangeError.checkValidRange(start, end, buffer.length);
    final count = (end ?? buffer.length) - start;

    final bytesRead = readSync(count);
    buffer.setAll(start, bytesRead);
    return bytesRead.length;
  }

  @override
  Future<_OpenedFile> setPosition(int position) {
    setPosition(position);
    return Future.value(this);
  }

  @override
  void setPositionSync(int position) {
    _checkCanStart();
    uring.binding
        .dartio_lseek(fd, position, SEEK_SET)
        .throwIfError(uring.binding);
  }

  @override
  Future<RandomAccessFile> truncate(int length) {
    truncateSync(length);
    return Future.value(this);
  }

  @override
  void truncateSync(int length) {
    _checkCanStart();
    uring.binding.dartio_ftruncate(fd, length).throwIfError(uring.binding);
  }

  @override
  Future<RandomAccessFile> unlock([int start = 0, int end = -1]) {
    throw UnimplementedError(
        'unlock is not currently supported under io_uring');
  }

  @override
  void unlockSync([int start = 0, int end = -1]) {
    throw UnimplementedError(
        'unlockSsync is not currently supported under io_uring');
  }

  @override
  Future<RandomAccessFile> writeByte(int value) {
    return writeFrom([value]);
  }

  @override
  int writeByteSync(int value) {
    writeFromSync([value]);
    return 1;
  }

  @override
  Future<RandomAccessFile> writeFrom(List<int> buffer,
      [int start = 0, int? end]) {
    RangeError.checkValidRange(start, end, buffer.length);
    _checkCanStart();

    return Future.sync(() async {
      final effectiveEnd = end ?? buffer.length;
      final length = effectiveEnd - start;

      final nativeBuffer =
          uring.allocator.allocateBytes(buffer, start, effectiveEnd);
      try {
        var totalBytesWritten = 0;

        while (totalBytesWritten < length) {
          totalBytesWritten += await uring.run(uring.write(
              fd,
              nativeBuffer.elementAt(totalBytesWritten),
              length - totalBytesWritten));
        }

        return this;
      } finally {
        uring.allocator.free(nativeBuffer);
      }
    });
  }

  @override
  void writeFromSync(List<int> buffer, [int start = 0, int? end]) {
    RangeError.checkValidRange(start, end, buffer.length);
    _checkCanStart();

    final effectiveEnd = end ?? buffer.length;
    final length = effectiveEnd - start;

    final nativeBuffer =
        uring.allocator.allocateBytes(buffer, start, effectiveEnd);
    try {
      var totalBytesWritten = 0;

      while (totalBytesWritten < length) {
        totalBytesWritten += uring.runSync(uring.write(
            fd,
            nativeBuffer.elementAt(totalBytesWritten),
            length - totalBytesWritten));
      }
    } finally {
      uring.allocator.free(nativeBuffer);
    }
  }

  @override
  Future<RandomAccessFile> writeString(String string,
      {Encoding encoding = utf8}) {
    return writeFrom(encoding.encode(string));
  }

  @override
  void writeStringSync(String string, {Encoding encoding = utf8}) {
    return writeFromSync(encoding.encode(string));
  }
}

class ReadFromFdStream extends IOStream<List<int>> {
  final int fd;

  /// The original file's path, used in error messages.
  final String? path;

  ReadFromFdStream(IOUringImpl ring, this.fd, {int? bytesToRead, this.path})
      : super(ring, bytesToRead: bytesToRead);

  @override
  Operation<int> read(Pointer<Uint8> buffer, int length) {
    return ring.read(fd, buffer, length, path: path);
  }

  @override
  Operation<int> readFixed(ManagedBuffer buffer, int length) {
    return ring.readFixed(fd, buffer, length, path: path);
  }
}

abstract class _WriterBase implements StreamConsumer<List<int>> {
  final Future<_OpenedFile> _fileFuture;
  _OpenedFile? _file;

  Uint8List get _buffer;
  int _offsetInBuffer = 0;

  _WriterBase(this._fileFuture);

  Future<void> _writeBuffer(_OpenedFile file, int start, int end);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    // Note: This writer is wrapped in an IO Sink from dart:io, which ensures
    // addStream() and close() are not misused.
    final file = _file ??= await _fileFuture;

    final completer = Completer<void>.sync();

    late StreamSubscription<List<int>> subscription;
    subscription = stream.listen(
      (event) async {
        var offset = 0;
        final typedEvent =
            event is Uint8List ? event : Uint8List.fromList(event);

        while (offset < typedEvent.length) {
          final canWriteIntoBuffer =
              min(_buffer.length - _offsetInBuffer, typedEvent.length - offset);
          _buffer.setAll(
              _offsetInBuffer,
              Uint8List.sublistView(
                  typedEvent, offset, offset + canWriteIntoBuffer));

          offset += canWriteIntoBuffer;
          _offsetInBuffer += canWriteIntoBuffer;

          if (_offsetInBuffer == _buffer.length) {
            // Buffer is full, write!
            subscription.pause();

            try {
              await _writeBuffer(file, 0, _buffer.length);
              subscription.resume();
              // ignore: avoid_catches_without_on_clauses
            } catch (e, s) {
              await subscription.cancel();
              completer.completeError(e, s);
            }

            _offsetInBuffer = 0;
          }
        }
      },
      onError: (Object error, StackTrace trace) {
        completer.completeError(error, trace);
        subscription.cancel();
      },
      onDone: () async {
        if (_offsetInBuffer != 0) {
          await _writeBuffer(file, 0, _offsetInBuffer);
        }

        if (!completer.isCompleted) completer.complete();
      },
    );

    return completer.future;
  }

  @override
  Future<void> close() {
    return _file?.close() ?? _fileFuture.then((f) => f.close());
  }
}

class _SharedMemoryFileWriter extends _WriterBase {
  final SharedBuffers _buffers;
  final ManagedBuffer _shared;

  @override
  Uint8List get _buffer => _shared.contents;

  _SharedMemoryFileWriter(this._buffers, Future<_OpenedFile> file, this._shared)
      : super(file);

  @override
  Future<void> _writeBuffer(_OpenedFile file, int start, int end) async {
    var offset = start;

    while (offset < end) {
      final bytesWritten = await file.uring.run(file.uring.writeFixed(
        file.fd,
        _shared,
        end - start,
        offsetInBuffer: start,
        path: file.path,
      ));

      offset += bytesWritten;
    }
  }

  @override
  Future<void> close() {
    return super.close().whenComplete(() {
      _buffers.returnBuffer(_shared);
    });
  }
}

class _RegularFileWriter extends _WriterBase {
  static const _bufferSize = 4096;

  @override
  final Uint8List _buffer = Uint8List(_bufferSize);

  _RegularFileWriter(Future<_OpenedFile> fileFuture) : super(fileFuture);

  @override
  Future<void> _writeBuffer(_OpenedFile file, int start, int end) {
    return file.writeFrom(_buffer, start, end);
  }
}
