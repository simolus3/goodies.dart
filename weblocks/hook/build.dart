import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) async {
  await build(args, (input, output) async {
    Future<void> useHostBuild() async {
      await _cargoBuild();

      final name = switch (Platform.operatingSystem) {
        'linux' => 'libdart_locks.so',
        'macos' => 'libdart_locks.dylib',
        'windows' => 'dart_locks.dll',
        _ => throw 'Unknown operating system',
      };
      final path = p.absolute('native/target/debug/$name');

      output.assets.code.add(
        CodeAsset(
          package: 'weblocks',
          name: 'src/native/bindings.dart',
          linkMode: DynamicLoadingSystem(Uri.file(path)),
        ),
      );

      final native = Directory('native');
      final dependencies = native.listSync().expand<String>((entry) sync* {
        if (p.basename(entry.path) == 'target') {
          return;
        }

        if (entry is Directory) {
          yield* entry
              .listSync(recursive: true)
              .whereType<File>()
              .map((e) => e.path);
        } else if (entry is File) {
          yield entry.path;
        }
      });
      output.dependencies.addAll(dependencies.map((p) => Uri.file(p)));
    }

    final localBuild = input.userDefines['local_build'] == true;
    if (localBuild || !Directory('assets').existsSync()) {
      await useHostBuild();
    } else {
      final os = input.config.code.targetOS;
      final builds = switch (os) {
        OS.macOS => _macosBuilds,
        OS.iOS =>
          input.config.code.iOS.targetSdk == IOSSdk.iPhoneOS
              ? _iosBuilds
              : _iosSimulatorBuilds,
        OS.android => _androidBuilds,
        OS.linux => _linuxBuilds,
        OS.windows => _windowsBuilds,
        OS(:final name) => throw UnsupportedError(
          'Operating system not supported: $name',
        ),
      };

      final targetArchitecture = input.config.code.targetArchitecture;
      final filename =
          builds[targetArchitecture] ??
          (throw UnsupportedError(
            'Architecture $targetArchitecture not supported for $os. Supported are: ${builds.keys}',
          ));

      output.assets.code.add(
        CodeAsset(
          package: 'weblocks',
          name: 'src/native/bindings.dart',
          file: Uri.file(p.absolute(p.join('assets', filename))),
          linkMode: DynamicLoadingBundled(),
        ),
      );
    }
  });
}

Future<void> _cargoBuild() async {
  final process = await Process.start(
    'cargo',
    ['build'],
    mode: ProcessStartMode.inheritStdio,
    workingDirectory: 'native',
  );

  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw 'Could not invoke cargo build';
  }
}

const _androidBuilds = {
  Architecture.arm: 'libdart_locks.android_v7a.so',
  Architecture.arm64: 'libdart_locks.android_v8a.so',
  Architecture.x64: 'libdart_locks.android_x86_64.so',
};

const _iosBuilds = {Architecture.arm64: 'libdart_locks.ios_aarch64.dylib'};

const _iosSimulatorBuilds = {
  Architecture.arm64: 'libdart_locks.ios_sim_aarch64.dylib',
  Architecture.x64: 'libdart_locks.ios_sim_x64.dylib',
};

const _macosBuilds = {
  Architecture.arm64: 'libdart_locks.macos_aarch64.dylib',
  Architecture.x64: 'libdart_locks.macos_x64.dylib',
};

const _linuxBuilds = {
  Architecture.arm: 'libdart_locks.linux_arm7.so',
  Architecture.arm64: 'libdart_locks.linux_aarch64.so',
  Architecture.x64: 'libdart_locks.linux_x64.so',
  Architecture.riscv64: 'libdart_locks.linux_riscv.so',
};

const _windowsBuilds = {
  Architecture.arm64: 'dart_locks.win_aarch64.dll',
  Architecture.x64: 'dart_locks.win_x64.dll',
};
