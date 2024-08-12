`shelf_multipart` parses multipart and `multipart/form-data` requests for shelf handlers.

## Handling multipart requests

Multipart requests are represented by the `MultipartRequest` extension type. To
check whether a request is a multipart request, `MultipartRequest.of` or
the `Request.multipart()` extension method can be used:

```dart
import 'package:shelf_multipart/shelf_multipart.dart';
import 'package:shelf/shelf.dart';

Future<Response> myHandler(Request request) async {
  if (request.multipart() case var multipart?) {
    // Iterate over parts making up this request:
    await for (final part in multipart.parts) {
      // Headers are available through part.headers as a map:
      final headers = part.headers;
      // part implements the `Stream<List<int>>` interface which can be used to
      // read data. You can also use `part.readBytes()` or `part.readString()`
    }
  } else {
    return Response(401); // not a multipart request
  }
}
```

## Handling `multipart/form-data`

Since form data is also sent as multipart requests, this package provides
methods to read form data as well:

```dart
if (request.formData() case var form?) {
  // Read all form-data parameters into a single map:
  final parameters = <String, String>{
    await for (final formData in form.formData)
     formData.name: await formData.part.readString(),
  };
}
```
