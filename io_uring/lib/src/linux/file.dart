import 'dart:ffi';

class open_how extends Struct {
  @Uint64()
  external int flags;
  @Uint64()
  external int mode;
  @Uint64()
  external int resolve;
}

const AT_FDCWD = -100;
const AT_SYMLINK_NOFOLLOW = 0x100;

const O_RDONLY = 0;
const O_WRONLY = 1;
const O_RDWR = 2;
const O_CREAT = 0x40;
const O_EXCL = 0x80;
const O_NOCTTY = 0x100;
const O_TRUNC = 0x200;
const O_APPEND = 0x400;

const SEEK_SET = 0;
const SEEK_CUR = 1;
const SEEK_END = 2;

// https://elixir.bootlin.com/linux/v5.15-rc7/source/include/uapi/linux/openat2.h#L26
const RESOLVE_NO_XDEV = 0x01;
const RESOLVE_NO_MAGICLINKS = 0x02;
const RESOLVE_NO_SYMLINKS = 0x04;
const RESOLVE_BENEATH = 0x08;
const RESOLVE_IN_ROOT = 0x10;
const RESOLVE_CACHED = 0x20;
