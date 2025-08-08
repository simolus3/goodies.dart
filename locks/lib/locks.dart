/// Support for doing something awesome.
///
/// More dartdocs go here.
library;

export 'src/interface.dart';

import 'src/interface.dart';
import 'src/unsupported.dart'
    if (dart.library.js_interop) 'src/web.dart'
    if (dart.library.ffi) 'src/native.dart';

LockManager get lockManager => lockManagerImpl;
