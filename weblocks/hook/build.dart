import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) async {
  await build(args, (input, output) async {
    final localBuild = input.userDefines['local_build'] == true;
    if (localBuild) {
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
      output.addDependencies(dependencies.map((p) => Uri.file(p)));
    } else {
      throw 'todo: download';
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
