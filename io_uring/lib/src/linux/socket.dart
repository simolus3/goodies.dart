import 'dart:io';

import 'dart:typed_data';

const AF_UNIX = 1;
const AF_INET = 2;
const AF_INET6 = 10;

const SOCK_STREAM = 1;
const SOCK_DGRAM = 2;

const SHUT_RD = 0;
const SHUT_WR = 1;
const SHUT_RDWR = 2;

extension ResolveType on InternetAddressType {
  int get linuxSocketType {
    switch (this) {
      case InternetAddressType.IPv4:
        return AF_INET;
      case InternetAddressType.IPv6:
        return AF_INET6;
      case InternetAddressType.unix:
        return AF_UNIX;
      default:
        throw ArgumentError('Unsupported address type: $this');
    }
  }
}

final _buffer = Uint8List(64).buffer;

/// Converts a 16-bit [int] [i] into a big-endian format for networking.
int htons(int i) {
  final data = _buffer.asByteData();
  data.setUint16(0, i, Endian.host);
  return data.getInt16(0);
}
