import 'dart:io';

import 'package:file/local.dart';
import 'package:find_in_git/find_in_git.dart';
import 'package:tar/tar.dart';

void main() async {
  const fs = LocalFileSystem();

  final index = RepositoryIndex();
  final repo = FileRepository(fs.currentDirectory.parent);
  await repo.loadIntoIndex(index);

  final search = RepositorySearch(index);
  final package = fs
      .file('/home/simon/Downloads/shelf_multipart-1.0.0.tar.gz')
      .openRead()
      .transform(gzip.decoder);
  await TarReader.forEach(package, (entry) async {
    if (entry.type == TypeFlag.reg) {
      await search.addFilter(entry.name, entry.size, entry.contents);
    }
  });

  final results = search.search();

  for (final result in results) {
    print(
        'Found potential result: ${result.commitId} in ${result.pathInRepository}');
  }
}
