import 'object_id.dart';
import 'objects.dart';

class RepositoryIndex {
  final Map<ObjectId, GitObject> knownObjects = {};

  final Set<ObjectId> commits = {};
  final Map<ObjectId, List<TreeEntry>> objectsUsedInTree = {};
  final Map<ObjectId, List<ObjectId>> treesToRevisions = {};
}
