import 'dart:ffi';

import 'dart:typed_data';

class iovec extends Struct {
  external Pointer<Void> iov_base;
  @IntPtr()
  external int iov_len;
}

class ManagedBuffer {
  final Pointer<iovec> buffer;
  final int index;

  final Uint8List contents;

  bool _isUsed = false;

  ManagedBuffer(this.buffer, this.index)
      : contents =
            buffer.ref.iov_base.cast<Uint8>().asTypedList(buffer.ref.iov_len);
}

/// Manages buffers shared between this program and the Kernel.
///
/// We can use shared buffers for some IO operations to avoid some copies.
class SharedBuffers {
  final List<ManagedBuffer> buffers;

  const SharedBuffers(this.buffers);

  ManagedBuffer? useBuffer() {
    for (final buffer in buffers) {
      if (buffer._isUsed) continue;

      return buffer.._isUsed = true;
    }
  }

  void returnBuffer(ManagedBuffer buffer) {
    buffer._isUsed = false;
  }
}
