// ignore_for_file: non_constant_identifier_names, constant_identifier_names

@Native()
library;

import 'dart:ffi';

@Native<Pointer<Void> Function(Size, Pointer<Uint8>, Pointer<Void>)>(
  isLeaf: true,
)
external Pointer<Void> pkg_locks_client(
  int length,
  Pointer<Uint8> name,
  Pointer<Void> dartDL,
);

@Native<Void Function(Pointer<Void>)>(isLeaf: true)
external void pkg_locks_free_client(Pointer<Void> client);

@Native<
  Pointer<Void> Function(Size, Pointer<Uint8>, Pointer<Void>, Uint32, Int64)
>(isLeaf: true)
external Pointer<Void> pkg_locks_obtain(
  int length,
  Pointer<Uint8> name,
  Pointer<Void> client,
  int flags,
  int port,
);

@Native<Void Function(Pointer<Void>)>(isLeaf: true)
external void pkg_locks_unlock(Pointer<Void> ptr);

@Native<Void Function(Uint64)>(isLeaf: true)
external void pkg_locks_snapshot(int port);

const FLAG_SHARED = 0x01;
const FLAG_STEAL = 0x02;
const FLAG_IF_AVAILABLE = 0x04;

final clientFinalizer = NativeFinalizer(
  Native.addressOf(pkg_locks_free_client),
);

final requestFinalizer = NativeFinalizer(Native.addressOf(pkg_locks_unlock));
