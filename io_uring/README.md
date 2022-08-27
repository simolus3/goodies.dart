# io_uring

This is an experiment to replace the IO implementation in `dart:io` with a
custom one built with `io_uring` on Linux.

Running this requires a somewhat recent kernel, as no compatibility checks are
included at the moment.

This project requires a custom native library. To compile it, run
`dart run build_runner build`.
