import 'dart:io';

import 'package:io_uring/io_uring.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  late IOUring ring;

  setUp(() async {
    ring = await IOUring.initialize();
  });
  tearDown(() => ring.dispose());

  group('exists', () {
    test('async', () async {
      await d.file('exists').create();

      await runWithIOUring(() async {
        expect(await File('${d.sandbox}/exists').exists(), isTrue);
        expect(await File('${d.sandbox}/no').exists(), isFalse);

        expect(await Directory('${d.sandbox}/exists').exists(), isFalse);
        expect(await Link('${d.sandbox}/exists').exists(), isFalse);
      }, ring);
    });

    test('sync', () async {
      await d.file('exists').create();

      runWithIOUring(() {
        expect(File('${d.sandbox}/exists').existsSync(), isTrue);
        expect(File('${d.sandbox}/no').existsSync(), isFalse);

        expect(Directory('${d.sandbox}/exists').existsSync(), isFalse);
        expect(Link('${d.sandbox}/exists').existsSync(), isFalse);
      }, ring);
    });
  });

  group('stat', () {
    test('async', () async {
      await d.file('exists').create();

      await runWithIOUring(() async {
        final stat = await File('${d.sandbox}/exists').stat();

        expect(stat.type, FileSystemEntityType.file);
        expect(stat.size, 0);

        final notExistingStat = await File('${d.sandbox}/no').stat();
        expect(notExistingStat.type, FileSystemEntityType.notFound);
      }, ring);
    });

    test('sync', () async {
      await d.file('exists').create();

      runWithIOUring(() {
        final stat = File('${d.sandbox}/exists').statSync();

        expect(stat.type, FileSystemEntityType.file);
        expect(stat.size, 0);

        final notExistingStat = File('${d.sandbox}/no').statSync();
        expect(notExistingStat.type, FileSystemEntityType.notFound);
      }, ring);
    });
  });

  group('delete', () {
    test('async', () async {
      await d.file('exists').create();

      await runWithIOUring(() => File('${d.sandbox}/exists').delete(), ring);
      await d.nothing('exists').validate();
    });

    test('sync', () async {
      await d.file('exists').create();

      runWithIOUring(() => File('${d.sandbox}/exists').deleteSync(), ring);
      await d.nothing('exists').validate();
    });
  });
}
