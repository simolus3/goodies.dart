import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    input.config.code.targetOS;
    output.assets.code.add(
      CodeAsset(
        package: 'locks',
        name: 'src/native/bindings.dart',
        linkMode: DynamicLoadingSystem(
          Uri.file(
            '/Users/simon/src/goodies.dart/locks/native/target/debug/libdart_locks.dylib',
          ),
        ),
      ),
    );
  });
}
