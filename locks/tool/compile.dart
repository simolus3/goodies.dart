import 'dart:io';

void main(List<String> args) async {
  final targetsByName = Target.values.asNameMap();

  if (args.isEmpty) {
    stderr
      ..writeln('Usage: dart tool/compile.dart <targets>')
      ..writeln('Supported targets: ${targetsByName.keys}')
      ..flush();
    exit(1);
  }

  for (final targetName in args) {
    final target = targetsByName[targetName];
    if (target == null) {
      stderr
        ..writeln('Unsupported target: $targetName')
        ..writeln('Supported targets: ${targetsByName.keys}')
        ..flush();
      exit(1);
    }

    for (final rustTarget in target.targets) {
      print('Building for $rustTarget');
      await _cargoBuild(rustTarget);
    }
  }
}

Future<void> _cargoBuild(String rustTarget) async {
  final process = await Process.start(
    'cargo',
    ['build', '--release', '--target', rustTarget],
    mode: ProcessStartMode.inheritStdio,
    workingDirectory: 'native',
  );

  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    stderr
      ..writeln('Could not invoke cargo for $rustTarget')
      ..flush();
    exit(1);
  }
}

enum Target {
  android([
    'aarch64-linux-android',
    'armv7-linux-androideabi',
    'x86_64-linux-android',
  ]),
  iOS(['aarch64-apple-ios', 'aarch64-apple-ios-sim', 'x86_64-apple-ios']),
  macOS(['aarch64-apple-darwin', 'x86_64-apple-darwin']),
  linux([
    'aarch64-unknown-linux-gnu',
    'x86_64-unknown-linux-gnu',
    'riscv64gc-unknown-linux-gnu',
    // 'armv7-unknown-linux-gnueabihf',
  ]),
  windows(['x86_64-pc-windows-msvc', 'aarch64-pc-windows-msvc']);

  final List<String> targets;

  const Target(this.targets);
}
