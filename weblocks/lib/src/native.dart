import 'interface.dart';
import 'native/implementation.dart';

final LockManager lockManagerImpl = NativeLockManager.forCurrentIsolate();
