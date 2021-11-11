// Version of the build script that runs the build under io_uring.

import 'dart:io' as _i6;
import 'dart:isolate' as _i4;

import 'package:build/build.dart' as _i3;
import 'package:build_runner/build_runner.dart' as _i5;
import 'package:build_runner_core/build_runner_core.dart' as _i1;
import 'package:io_uring/io_uring.dart';

import 'compiler.dart' as _i2;

final _builders = <_i1.BuilderApplication>[
  _i1.apply(r'io_uring:compiler', [_i2.cc], _i1.toRoot(),
      hideOutput: true,
      defaultOptions: const _i3.BuilderOptions(<String, dynamic>{
        r'args': r'-Wall -Wextra -Werror -g -fPIC -o $output -c $input',
        r'build_extensions': {
          r'.c': [r'.o']
        }
      }),
      defaultReleaseOptions: const _i3.BuilderOptions(
          <String, dynamic>{r'args': r'-O3 -fPIC -o $output -c $input'})),
  _i1.apply(r'io_uring:linker', [_i2.cc], _i1.toRoot(),
      hideOutput: false,
      defaultOptions: const _i3.BuilderOptions(<String, dynamic>{
        r'args': r'-shared -o $output $input',
        r'build_extensions': {
          r'{{dir}}/{{name}}.o': [r'{{dir}}/lib{{name}}.so']
        }
      }))
];
Future<void> main(List<String> args, [_i4.SendPort? sendPort]) async {
  final ring = await IOUring.initialize();

  final result = await runWithIOUring(() => _i5.run(args, _builders), ring);
  sendPort?.send(result);
  _i6.exitCode = result;
}
