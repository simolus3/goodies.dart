import 'dart:convert';

import 'package:find_in_git/find_in_git.dart';
import 'package:test/test.dart';

void main() {
  group('blob', () {
    test('synchronous', () {
      // echo -n "what is up, doc?" | git hash-object --stdin
      expect(ObjectId.blobSync(utf8.encode('what is up, doc?')),
          ObjectId.hex('bd9dbf5aae1a3862dd1526723246b20206e5fc37'));
    });

    test('asynchronous', () async {
      const length = 16;
      final objectId = await Stream.fromIterable(['what is up, ', 'doc?'])
          .transform(utf8.encoder)
          .transform(ObjectId.blob(length))
          .first;

      expect(
          objectId, ObjectId.hex('bd9dbf5aae1a3862dd1526723246b20206e5fc37'));
    });
  });
}
