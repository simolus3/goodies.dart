`shelf_multipart` parses multipart and `multipart/form-data` requests for shelf handlers.

## Handling multipart requests

To handle multipart requests, use the `ReadMultipartRequest` extension from the
`package:shelf_multipart/multipart.dart` library:

```dart
import 'package:shelf_multipart/multipart.dart';
import 'package:shelf/shelf.dart';

Future<Response> myHandler(Request request) async {
  if (!request.isMultipart) {
    return Response(401); // not a multipart request
  }

  // Iterate over parts making up this request:
  await for (final part in request.parts) {
    // Headers are available through part.headers as a map:
    final headers = part.headers;
    // part implements the `Stream<List<int>>` interface which can be used to
    // read data. You can also use `part.readBytes()` or `part.readString()`
  }
}
```

## Handling `multipart/form-data`

To parse form-data multipart requests, use the `package:shelf_multipart/form_data.dart` library:

```dart
if (request.isMultipartForm) {
  // Read all form-data parameters into a single map:
  final parameters = <String, String>{
    await for (final formData in request.multipartFormData)
     formData.name: await formData.part.readString(),
  };
}
```
