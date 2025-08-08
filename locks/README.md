# Locks

`package:locks` is a mutex implementation that:

- works across isolates on native platforms, and across tabs and workers on the web.
- is asynchronous.
- supports shared and exclusive access to locks.
- identifies mutexes by name, and doesn't require prior communication.
- can query the state of mutexes.

On the web, `package:locks` is implemented with of the [Web Locks API](https://w3c.github.io/web-locks).
On native platforms, `dart:ffi` is used with a native lock implementation written in Rust.
Of course, both platforms use an identical API, and behave similarly.

## Getting started

Note that this package requires the `native-assets` experiment, meaning that it is currently only
available on dev builds of the Dart SDK.

Apart from that, `dart pub add locks` is the only step to install this package. Build hooks will
automatically download native sources where required.

## Usage

The `LockManager` interface is the main entrypoint to request locks, available through the `lockManager`
getter:

```dart
import 'package:locks/locks.dart';

void main() async {
  final lockName = 'my-lock';

  final held = await lockManager.request(lockName).completion;
  print('Holds lock: ${held != null}'); // true

  held!.release();
}
```

For more details, see the documentation or the full example.
