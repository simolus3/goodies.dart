import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// A pure-Dart implementation of the ChaCha20 algorithm as specified by RFC
/// 7539.
///
/// To encrypt or decrypt a full message, call [encrypt] or [decrypt].
/// This codec supports an optimized, memory-efficient conversion of streaming
/// data as well:
///
/// ```dart
/// late final List<int> encrypted;
/// final outputSink = ByteConversionSink.withCallback((r) => encrypted = r);
/// final encryptingSink = ChaCha20(key, iv).encoder
///     .startChunkedConversion(outputSink);
/// for (List<int> event in messages) {
///   encryptingSink.add(event);
/// }
/// encryptingSink.close();
///
/// // encrypted data is now available in encrypted
/// ```
///
/// Chunked conversions are especially efficient for streams:
///
/// ```dart
/// Stream<List<int>> encrypt(Stream<String> input) {
///   final enc = utf8.fuse(ChaCha20(key, iv)).encoder;
///   return input.transform(enc);
/// }
/// ```
class ChaCha20 extends Codec<List<int>, List<int>> {
  final Uint8List _key;
  final Uint8List _iv;
  final int _initialCounter;

  ChaCha20(this._key, this._iv, {int initialCounter = 0})
      : _initialCounter = initialCounter {
    if (_key.length != 32) {
      throw ArgumentError('Must have a length of 32', 'key');
    }

    if (_iv.length != 12) {
      throw ArgumentError('Must have a length of 12', 'iv');
    }
  }

  @override
  Converter<List<int>, List<int>> get decoder =>
      _Converter(_key, _iv, _initialCounter);

  @override
  Converter<List<int>, List<int>> get encoder => decoder;

  /// Encrypts the [plaintext] bytes with the ChaCha20 algorithm, using the key,
  /// IV and initial counter set in the [ChaCha20] constructor.
  ///
  /// As this is a symmetric encryption scheme, this is equivalent to [decrypt].
  List<int> encrypt(List<int> plaintext) {
    return encoder.convert(plaintext);
  }

  /// Decrypts the [plaintext] bytes with the ChaCha20 algorithm, using the key,
  /// IV and initial counter set in the [ChaCha20] constructor.
  ///
  /// As this is a symmetric encryption scheme, this is equivalent to [encrypt].
  List<int> decrypt(List<int> ciphertext) {
    return encrypt(ciphertext);
  }
}

class _Converter extends Converter<List<int>, List<int>> {
  final Uint8List key;
  final Uint8List iv;
  final int initialBlock;

  _Converter(this.key, this.iv, this.initialBlock);

  @override
  Uint8List convert(List<int> input) {
    final output = Uint8List(input.length);
    final sink = _FixedLengthByteSink(output);

    startChunkedConversion(sink)
      ..add(input)
      ..close();

    return output;
  }

  @override
  Sink<List<int>> startChunkedConversion(Sink<List<int>> sink) {
    final generator = _KeyStreamGenerator(key, iv, initialBlock);

    if (sink is ByteConversionSink) {
      return _ChaCha20ConversionSink(sink, generator);
    } else {
      return _RegularChaCha20Sink(sink, generator);
    }
  }
}

const _stateLengthInWords = 16;
const _stateLengthInBytes = _stateLengthInWords * 4;

/// ChaCha20 works by generating a random byte array from an internal state.
///
/// This byte array is then xor-ed with the message for encryption or
/// decryption.
class _KeyStreamGenerator {
  final Uint8List key;
  final Uint8List nonce;

  final Uint32List _previousState = Uint32List(_stateLengthInWords);
  final Uint32List state = Uint32List(_stateLengthInWords);

  /// The serialized [state], which forms the current block in the key stream.
  ///
  /// A memory-optimized sink may directly mutate this array by xor-ing a
  /// message into this. The state will be reset when [nextBlock] is called.
  final Uint8List serializedState = Uint8List(_stateLengthInBytes);

  int blockCounter;

  _KeyStreamGenerator(this.key, this.nonce, [this.blockCounter = 0]);

  /// Encodes the key, nonce and counter into the [_state] matrix.
  void _createState() {
    // The first four words are constants:
    state[0] = 0x61707865;
    state[1] = 0x3320646e;
    state[2] = 0x79622d32;
    state[3] = 0x6b206574;

    // The next eight words are taken from the key by reading it in 4-byte
    // chunks (little endian).
    final keyData = key.buffer.asByteData(key.offsetInBytes);
    for (var i = 0; i < 8; i++) {
      state[4 + i] = keyData.getUint32(i * 4, Endian.little);
    }

    // Word 12 is a block counter
    state[12] = blockCounter;

    // Words 13-15 are a nonce
    final nonceData = nonce.buffer.asByteData(nonce.offsetInBytes);
    for (var i = 0; i < 3; i++) {
      state[13 + i] = nonceData.getUint32(i * 4, Endian.little);
    }
  }

  /// Performs 20 quarter rounds (interleaved with column and diagonal rounds).
  void _shuffleState() {
    var x00 = state[0];
    var x01 = state[1];
    var x02 = state[2];
    var x03 = state[3];
    var x04 = state[4];
    var x05 = state[5];
    var x06 = state[6];
    var x07 = state[7];
    var x08 = state[8];
    var x09 = state[9];
    var x10 = state[10];
    var x11 = state[11];
    var x12 = state[12];
    var x13 = state[13];
    var x14 = state[14];
    var x15 = state[15];

    for (var i = 10; i > 0; i--) {
      // QUARTERROUND ( 0, 4, 8,12)
      x00 += x04;
      x12 = (x12 ^ x00).rotateLeft32(16);
      x08 += x12;
      x04 = (x04 ^ x08).rotateLeft32(12);
      x00 += x04;
      x12 = (x12 ^ x00).rotateLeft32(8);
      x08 += x12;
      x04 = (x04 ^ x08).rotateLeft32(7);

      // QUARTERROUND ( 1, 5, 9,13)
      x01 += x05;
      x13 = (x13 ^ x01).rotateLeft32(16);
      x09 += x13;
      x05 = (x05 ^ x09).rotateLeft32(12);
      x01 += x05;
      x13 = (x13 ^ x01).rotateLeft32(8);
      x09 += x13;
      x05 = (x05 ^ x09).rotateLeft32(7);

      // QUARTERROUND ( 2, 6,10,14)
      x02 += x06;
      x14 = (x14 ^ x02).rotateLeft32(16);
      x10 += x14;
      x06 = (x06 ^ x10).rotateLeft32(12);
      x02 += x06;
      x14 = (x14 ^ x02).rotateLeft32(8);
      x10 += x14;
      x06 = (x06 ^ x10).rotateLeft32(7);

      // QUARTERROUND ( 3, 7,11,15)
      x03 += x07;
      x15 = (x15 ^ x03).rotateLeft32(16);
      x11 += x15;
      x07 = (x07 ^ x11).rotateLeft32(12);
      x03 += x07;
      x15 = (x15 ^ x03).rotateLeft32(8);
      x11 += x15;
      x07 = (x07 ^ x11).rotateLeft32(7);

      // QUARTERROUND ( 0, 5,10,15)
      x00 += x05;
      x15 = (x15 ^ x00).rotateLeft32(16);
      x10 += x15;
      x05 = (x05 ^ x10).rotateLeft32(12);
      x00 += x05;
      x15 = (x15 ^ x00).rotateLeft32(8);
      x10 += x15;
      x05 = (x05 ^ x10).rotateLeft32(7);

      // QUARTERROUND ( 1, 6,11,12)
      x01 += x06;
      x12 = (x12 ^ x01).rotateLeft32(16);
      x11 += x12;
      x06 = (x06 ^ x11).rotateLeft32(12);
      x01 += x06;
      x12 = (x12 ^ x01).rotateLeft32(8);
      x11 += x12;
      x06 = (x06 ^ x11).rotateLeft32(7);

      // QUARTERROUND ( 2, 7, 8,13)
      x02 += x07;
      x13 = (x13 ^ x02).rotateLeft32(16);
      x08 += x13;
      x07 = (x07 ^ x08).rotateLeft32(12);
      x02 += x07;
      x13 = (x13 ^ x02).rotateLeft32(8);
      x08 += x13;
      x07 = (x07 ^ x08).rotateLeft32(7);

      // QUARTERROUND ( 3, 4, 9,14)
      x03 += x04;
      x14 = (x14 ^ x03).rotateLeft32(16);
      x09 += x14;
      x04 = (x04 ^ x09).rotateLeft32(12);
      x03 += x04;
      x14 = (x14 ^ x03).rotateLeft32(8);
      x09 += x14;
      x04 = (x04 ^ x09).rotateLeft32(7);
    }

    state[0] = x00;
    state[1] = x01;
    state[2] = x02;
    state[3] = x03;
    state[4] = x04;
    state[5] = x05;
    state[6] = x06;
    state[7] = x07;
    state[8] = x08;
    state[9] = x09;
    state[10] = x10;
    state[11] = x11;
    state[12] = x12;
    state[13] = x13;
    state[14] = x14;
    state[15] = x15;
  }

  /// Creates a new block in the keystream.
  ///
  /// The block will be written into [_serializedState].
  void nextBlock() {
    // Create the new state, and store a copy of it in previousState before
    // mutating it.
    _createState();
    final newList = state.buffer.asInt32x4List();
    final oldList = _previousState.buffer.asInt32x4List();
    assert(newList.length == 4 && oldList.length == 4);

    // Copy the state into the old list before shuffling it
    for (var i = 0; i < 4; i++) {
      oldList[i] = newList[i];
    }

    _shuffleState();

    // Add the previous state to the current state, 4 words at a time

    for (var i = 0; i < 4; i++) {
      newList[i] = newList[i] + oldList[i];
    }

    // Write the serialized state, encoding each number in little endian order
    final serializedData = serializedState.buffer.asByteData();
    for (var i = 0; i < 16; i++) {
      serializedData.setUint32(i * 4, state[i], Endian.little);
    }

    blockCounter++;
  }
}

/// XORs a full block of 16 words from [dest] and [other] into [dest].
void _xorFullBlock(
    Uint8List dest, int destOffset, Uint8List other, int otherOffset) {
  final effectiveDestOffset = dest.offsetInBytes + destOffset;
  final effectiveOtherOffset = other.offsetInBytes + otherOffset;

  if (effectiveDestOffset % 16 == 0 && effectiveOtherOffset % 16 == 0) {
    // We can xor 256 bit at once using SIMD instructions.
    final dest32x4 = dest.buffer.asInt32x4List(effectiveDestOffset, 4);
    final other32x4 = other.buffer.asInt32x4List(effectiveOtherOffset, 4);

    dest32x4[0] ^= other32x4[0];
    dest32x4[1] ^= other32x4[1];
    dest32x4[2] ^= other32x4[2];
    dest32x4[3] ^= other32x4[3];
  } else {
    // Fall back to a byte-by-byte xor
    for (var i = 0; i < 16; i++) {
      dest[destOffset + i] ^= other[i];
    }
  }
}

/// A ChaCha20 sink emitting into a general [Sink].
///
/// This will copy incoming chunks.
class _RegularChaCha20Sink extends Sink<List<int>> {
  final Sink<List<int>> output;
  final _KeyStreamGenerator generator;

  int _remainingInCurrentKeyStreamBlock = 0;

  _RegularChaCha20Sink(this.output, this.generator);

  @override
  void add(List<int> chunk) {
    // Create a copy which we can then encrypt in-place.
    final typedCopy = Uint8List.fromList(chunk);
    var offset = 0;

    // XOR the message with the key stream. Start by using up the current block,
    // if available.
    final canTakeFromCurrent =
        min(_remainingInCurrentKeyStreamBlock, chunk.length);
    final offsetInRemaining =
        _stateLengthInBytes - _remainingInCurrentKeyStreamBlock;
    for (var i = 0; i < canTakeFromCurrent; i++) {
      typedCopy[i] ^= generator.serializedState[offsetInRemaining + i];
    }

    _remainingInCurrentKeyStreamBlock -= canTakeFromCurrent;
    offset += canTakeFromCurrent;

    // Efficiently xor full message blocks that might remain
    while (offset + _stateLengthInBytes < typedCopy.length) {
      generator.nextBlock();
      _xorFullBlock(typedCopy, offset, generator.serializedState, 0);
      offset += _stateLengthInBytes;
    }

    // Start an incomplete block for the rest of the message.
    if (offset < typedCopy.length) {
      final remaining = typedCopy.length - offset;

      generator.nextBlock();

      for (var i = 0; i < remaining; i++) {
        typedCopy[offset + i] ^= generator.serializedState[i];
      }
      _remainingInCurrentKeyStreamBlock = _stateLengthInBytes - remaining;
    }

    output.add(typedCopy);
  }

  @override
  void close() {
    output.close();
  }
}

/// A ChaCha20 sink not allocating additional memory for encryption.
///
/// Messages are xor-ed onto the internal state of the [generator] which is
/// then passed to a downstream sink in [output].
class _ChaCha20ConversionSink extends ByteConversionSinkBase {
  final ByteConversionSink output;
  final _KeyStreamGenerator generator;

  int _offsetInState = _stateLengthInBytes;

  _ChaCha20ConversionSink(this.output, this.generator);

  @override
  void add(List<int> chunk) {
    addSlice(chunk, 0, chunk.length, false);
  }

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    var offsetInChunk = start;
    final serializedState = generator.serializedState;

    // Use up the remaining bytes in the available key stream block
    final remainingInState = _stateLengthInBytes - _offsetInState;
    if (remainingInState != 0) {
      final available = min(end - offsetInChunk, remainingInState);

      for (var i = 0; i < available; i++) {
        serializedState[_offsetInState + i] ^= chunk[offsetInChunk + i];
      }

      offsetInChunk += available;
      output.addSlice(
          serializedState, _offsetInState, _offsetInState += available, false);
    }

    // Continue going in full blocks.
    while (offsetInChunk + _stateLengthInBytes < end) {
      generator.nextBlock();

      if (chunk is Uint8List) {
        _xorFullBlock(serializedState, 0, chunk, offsetInChunk);
      } else {
        for (var i = 0; i < _stateLengthInBytes; i++) {
          serializedState[i] ^= chunk[offsetInChunk + i];
        }
      }

      output.addSlice(serializedState, 0, _stateLengthInBytes, false);
      offsetInChunk += _stateLengthInBytes;
    }

    // Write the remainder of the chunk not fitting into a block.
    final remaining = end - offsetInChunk;
    if (remaining > 0) {
      generator.nextBlock();

      for (var i = 0; i < remaining; i++) {
        serializedState[i] ^= chunk[offsetInChunk + i];
      }
      output.addSlice(serializedState, 0, remaining, isLast);
      _offsetInState = remaining;
    }
  }

  @override
  void close() {
    output.close();
  }
}

class _FixedLengthByteSink extends ByteConversionSinkBase {
  final Uint8List target;
  int _offset = 0;

  _FixedLengthByteSink(this.target);

  @override
  void add(List<int> chunk) {
    target.setAll(_offset, chunk);
    _offset += chunk.length;
  }

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    target.setAll(_offset, chunk.sublist(start, end));
    _offset += end - start;
  }

  @override
  void close() {}
}

extension on int {
  int rotateLeft32(int amount) {
    return this << amount | (toUnsigned(32) >> (32 - amount));
  }
}
