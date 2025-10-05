# Locks

`package:weblocks` ports web concurrency primitives to all Dart platforms.

This package includes a read-write lock implementation that:

- works across isolates on native platforms, and across tabs and workers on the web.
- is asynchronous.
- supports shared and exclusive access to locks.
- identifies mutexes by name, and doesn't require prior communication or `SendPort` setup.
- can query the state of mutexes.

On the web, `package:weblocks` is implemented with of the [Web Locks API](https://w3c.github.io/web-locks).
On native platforms, `dart:ffi` is used with a native lock implementation written in Rust.
Of course, both platforms use an identical API, and share tests to behave the same.

In addition to locks, this package also ports the `BroadcastChannel` API to native platforms.

## Getting started

Note that this package requires the `native-assets` experiment, meaning that it is currently only
available on beta builds of the Dart SDK.

Apart from that, `dart pub add weblocks` is the only step to install this package. Build hooks will
automatically download native sources where required.

## Usage

The `LockManager` interface is the main entrypoint to request locks, available through the `lockManager`
getter:

```dart
import 'package:weblocks/weblocks.dart';

void main() async {
  final lockName = 'my-lock';

  final held = await lockManager.request(lockName).completion;
  print('Holds lock: ${held != null}'); // true

  held!.release();
}
```

### Broadcast channels

To exchange broadcast messages between isolates, use `BroadcastChannel` instances created
through `LockManager.broadcastChannel`:

```dart
// These methods can run on different isolates, tabs, or web workers.
void send() {
  final channel = lockManager.broadcastChannel('foo');
  channel.send('hello');
}

void receive() async {
  final channel = lockManager.broadcastChannel('foo');
  await for (final message in channel) {
    print('From channel: $message');
  }
}
```

For more details, see the documentation or the full example.

## Development

To work on this package, consider adding the `hooks` section in the `pubspec.yaml`
that is currently commented out to use a debug build of the native code for the
current host.
