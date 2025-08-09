// ignore_for_file: non_constant_identifier_names, constant_identifier_names

@Native()
library;

import 'dart:ffi';

@Native<Pointer<Void> Function(Size, Pointer<Uint8>, Pointer<Void>)>(
  isLeaf: true,
)
external Pointer<Void> pkg_weblocks_client(
  int length,
  Pointer<Uint8> name,
  Pointer<Void> dartDL,
);

@Native<Void Function(Pointer<Void>)>(isLeaf: true)
external void pkg_weblocks_free_client(Pointer<Void> client);

@Native<
  Pointer<Void> Function(Size, Pointer<Uint8>, Pointer<Void>, Uint32, Int64)
>()
external Pointer<Void> pkg_weblocks_obtain(
  int length,
  Pointer<Uint8> name,
  Pointer<Void> client,
  int flags,
  int port,
);

@Native<Void Function(Pointer<Void>)>()
external void pkg_weblocks_unlock(Pointer<Void> ptr);

@Native<Void Function(Pointer<Void>, Uint64)>(isLeaf: true)
external void pkg_weblocks_snapshot(Pointer<Void> client, int port);

const FLAG_SHARED = 0x01;
const FLAG_STEAL = 0x02;
const FLAG_IF_AVAILABLE = 0x04;

final clientFinalizer = NativeFinalizer(
  Native.addressOf(pkg_weblocks_free_client),
);

final requestFinalizer = NativeFinalizer(Native.addressOf(pkg_weblocks_unlock));
