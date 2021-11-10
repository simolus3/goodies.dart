import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:scratch_space/scratch_space.dart';

const _compiler = 'cc';

final _compileSpace =
    Resource(() => ScratchSpace(), dispose: (old) => old.delete());

Builder cc(BuilderOptions options) {
  return _InvokeCC(
    (options.config['args'] as String).split(' '),
    {
      for (final entry in (options.config['build_extensions'] as Map).entries)
        entry.key as String: (entry.value as List).cast(),
    },
  );
}

class _InvokeCC implements Builder {
  final List<String> arguments;
  @override
  final Map<String, List<String>> buildExtensions;

  _InvokeCC(this.arguments, this.buildExtensions);

  @override
  Future<void> build(BuildStep buildStep) async {
    final space = await buildStep.fetchResource(_compileSpace);
    await space.ensureAssets([buildStep.inputId], buildStep);

    final input = space.fileFor(buildStep.inputId);
    final outputId = buildStep.allowedOutputs.single;
    final output = space.fileFor(outputId);

    final args = arguments.replaceInputAndOutput(input, output);
    log.info('Running cc $args');
    final proc = await Process.start(_compiler, args,
        workingDirectory: space.tempDir.path);
    await proc.runAndLog();

    await space.copyOutput(outputId, buildStep);
  }
}

extension on List<String> {
  List<String> replaceInputAndOutput(File input, File output) {
    return map((e) {
      if (e == r'$input') {
        return input.absolute.path;
      } else if (e == r'$output') {
        return output.absolute.path;
      } else {
        return e;
      }
    }).toList();
  }
}

extension on Process {
  Future<void> runAndLog() async {
    unawaited(this.stdout.logWith(log.info));
    unawaited(this.stderr.logWith(log.warning));

    final code = await this.exitCode;
    if (code != 0) {
      throw StateError('Unexpected return code: $code');
    }
  }
}

extension on Stream<List<int>> {
  Future<void> logWith(void Function(String) log) {
    // We're not outputing every line individually because that adds lots of
    // noise.
    final buffer = StringBuffer();
    return transform(utf8.decoder).forEach(buffer.write).then((void _) {
      log(buffer.toString());
    });
  }
}
