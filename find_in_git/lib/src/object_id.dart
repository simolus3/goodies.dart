import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart' as convert;

const _hash = sha1;

class ObjectId {
  final Digest _digest;

  ObjectId(this._digest);

  factory ObjectId.hex(String hex) {
    final result = convert.hex.decode(hex);
    if (result.length != 20) {
      throw ArgumentError.value(hex, 'hex',
          'Must be 20 bytes in length, actually was ${result.length}');
    }

    return ObjectId(Digest(result));
  }

  factory ObjectId.blobSync(List<int> data) {
    late Digest result;
    final header = utf8.encode('blob ${data.length}\u0000');
    final hash = _hash.startChunkedConversion(
        ChunkedConversionSink.withCallback(
            ((accumulated) => result = accumulated.single)));
    hash
      ..add(header)
      ..add(data)
      ..close();
    return ObjectId(result);
  }

  @override
  String toString() => _digest.toString();

  @override
  int get hashCode => _digest.hashCode;

  @override
  bool operator ==(Object other) {
    return other is ObjectId && other._digest == _digest;
  }

  static StreamTransformer<List<int>, ObjectId> blob(int length) {
    final header = utf8.encode('blob $length\u0000');

    return StreamTransformer.fromBind((source) async* {
      late Digest result;

      final conversion = _hash.startChunkedConversion(
          ChunkedConversionSink.withCallback(
              ((accumulated) => result = accumulated.single)));
      conversion.add(header);

      await for (final event in source) {
        conversion.add(event);
      }
      conversion.close();

      yield ObjectId(result);
    });
  }
}
