import '../index.dart';
import '../object_id.dart';
import '../objects.dart';

abstract class GitRepository {
  Future<GitObject?> read(ObjectId id);
  Stream<ObjectId> get commits;

  Future<void> loadIntoIndex(RepositoryIndex index) async {
    // We're essentially running a DFS on git objects here
    final queue = <ObjectId>[];

    void discover(ObjectId objectId) {
      if (!index.knownObjects.containsKey(objectId)) {
        queue.add(objectId);
      }
    }

    // Starting with commit ids as roots
    await for (final commitHash in commits) {
      discover(commitHash);
      index.commits.add(commitHash);
    }

    while (queue.isNotEmpty) {
      final key = queue.removeLast();

      if (!index.knownObjects.containsKey(key)) {
        final object = await read(key);
        if (object == null) continue;

        index.knownObjects[key] = object;

        if (object is Commit) {
          discover(object.treeId);
          index.treesToRevisions
              .putIfAbsent(object.treeId, () => [])
              .add(object.id);
        } else if (object is Tree) {
          for (final entry in object.entries) {
            discover(entry.reference);
            index.objectsUsedInTree
                .putIfAbsent(entry.reference, () => [])
                .add(entry);
          }
        }
      }
    }
  }
}
