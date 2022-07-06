import 'index.dart';
import 'object_id.dart';
import 'objects.dart';

import 'package:path/path.dart' show url;

class RepositorySearch {
  final RepositoryIndex index;
  final List<SearchFailure> failures = [];

  final _SearchDirectoryNode _rootNode = _SearchDirectoryNode('', '', null);

  RepositorySearch(this.index);

  _SearchFileNode _nodeForFile(String path) {
    final segments = url.split(path);
    var directory = _rootNode;

    for (var i = 0; i < segments.length - 1; i++) {
      final segment = segments[i];

      final child = directory.children.putIfAbsent(
        segment,
        () => _SearchDirectoryNode(
            url.joinAll(segments.take(i + 1)), segment, directory),
      );

      if (child is! _SearchDirectoryNode) {
        throw StateError(
            'Expected a directory at $path, but there is a file there.');
      }

      directory = child;
    }

    final node = directory.children.putIfAbsent(
        segments.last, () => _SearchFileNode(path, segments.last, directory));
    if (node is! _SearchFileNode) {
      throw StateError('Expected a file node at $path, found a directory.');
    }

    return node;
  }

  void _reconcile(_SearchEntityNode node) {
    if (node.allPossibleCandidates.isEmpty) {
      failures.add(SearchFailure('todo'));
      return;
    }

    final parent = node.parent;
    if (parent == null) return;

    // If this parent already had a list of possible matches, make sure that any
    // of them allows this node to exist as a child.
    if (parent.allPossibleCandidates.isNotEmpty) {
      final plausibleCandidates = <ObjectId>{};

      for (final plausibleParentId in parent.allPossibleCandidates) {
        final treeNode = index.knownObjects[plausibleParentId] as Tree;
        final isPlausible = treeNode.entries.any((entry) =>
            entry.name == node.name &&
            node.allPossibleCandidates.contains(entry.reference));

        if (isPlausible) {
          plausibleCandidates.add(plausibleParentId);
        }
      }

      if (plausibleCandidates.isEmpty) {
        // We've checked this parent already
        failures.add(SearchFailure('todo'));
      } else {
        parent.allPossibleCandidates = plausibleCandidates;
      }
    } else {
      final potentialParents = node.allPossibleCandidates
          .expand<TreeEntry>((id) => index.objectsUsedInTree[id] ?? const [])
          .where((element) => element.name == node.name)
          .map((e) => e.tree.id)
          .toSet();

      if (potentialParents.isNotEmpty) {
        parent.allPossibleCandidates = potentialParents;
      } else {
        failures.add(SearchFailure('todo: No parent found for file'));
      }
    }

    _reconcile(parent);
  }

  Future<void> addFilter(
      String path, int contentLength, Stream<List<int>> contents) async {
    final blobId = await contents.transform(ObjectId.blob(contentLength)).first;

    // See if this blob is contained in the repository
    if (!index.knownObjects.containsKey(blobId)) {
      failures.add(SearchFailure(
          'No matching file for $path was found in the repository.'));
      return;
    }

    final node = _nodeForFile(path);
    node.allPossibleCandidates = {blobId};
    _reconcile(node);
  }

  Iterable<SearchResult> _findCommitsReferencing(
      ObjectId id, List<String> pathStack) sync* {
    var parents = index.objectsUsedInTree[id] ?? const [];
    if (parents.isNotEmpty) {
      for (final parent in parents) {
        pathStack.add(parent.name);
        yield* _findCommitsReferencing(parent.tree.id, pathStack);
        pathStack.removeLast();
      }
    } else {
      final commits = index.treesToRevisions[id];
      if (commits != null) {
        for (final commit in commits) {
          yield SearchResult(commit, url.joinAll(pathStack.reversed));
        }
      }
    }
  }

  List<SearchResult> search() {
    return _rootNode.allPossibleCandidates
        .expand((id) => _findCommitsReferencing(id, []))
        .toList();
  }
}

class SearchFailure {
  final String message;

  SearchFailure(this.message);
}

abstract class _SearchEntityNode {
  final String pathInPackage;
  final String name;
  final _SearchDirectoryNode? parent;

  Set<ObjectId> allPossibleCandidates = const {};

  _SearchEntityNode(this.pathInPackage, this.name, this.parent);
}

class _SearchDirectoryNode extends _SearchEntityNode {
  final Map<String, _SearchEntityNode> children = {};

  _SearchDirectoryNode(super.pathInPackage, super.name, super.parent);
}

class _SearchFileNode extends _SearchEntityNode {
  _SearchFileNode(super.pathInPackage, super.name, super.parent);
}

class SearchResult {
  final ObjectId commitId;
  final String pathInRepository;

  SearchResult(this.commitId, this.pathInRepository);
}
