import 'dart:ffi';

import 'dart:typed_data';

extension AllocatorUtils on Allocator {
  Pointer<Uint8> allocateBytes(List<int> bytes, [int start = 0, int? end]) {
    final effectiveEnd = end ?? bytes.length;
    final length = effectiveEnd - start;

    final buffer = allocate<Uint8>(length);
    final dartView = buffer.asTypedList(length);

    if (bytes is Uint8List) {
      dartView.setAll(
          0, bytes.buffer.asUint8List(bytes.offsetInBytes + start, length));
    } else {
      for (var i = 0; i < length; i++) {
        dartView[i] = bytes[i + start];
      }
    }

    return buffer;
  }
}
