/// Support for doing something awesome.
///
/// More dartdocs go here.
library;

export 'src/interface.dart';

import 'src/interface.dart';
import 'src/unsupported.dart' if (dart.library.io) 'src/native.dart';
//if (dart.library.js_interop) 'src/unsupported.dart';

LockManager get lockManager => lockManagerImpl;
