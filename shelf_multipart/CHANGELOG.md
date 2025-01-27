## 2.0.1

- Support version 2.x of the `mime` package.

## 2.0.0

- __Breaking__: The two libraries have been merged into one,
  `package:shelf_multipart/shelf_multipart.dart`.
- Use extension types instead of extensions, which offers type safety around
  the `isMultipart` and `isMultipartForm` checks.
  Use `Request.formData()` or `Request.multipart()` and check for non-null
  return values to handle multipart requests now:
  ```dart
    Future<Response> handleReqeuest(Request request) async {
      if (request.formData() case var form?) {
        await for (final formData in form.formData) {
          print('${formData.name}: ${await formData.part.readString()}');
        }

        return Response.ok();
      } else {
        return Response.badRequest(body: 'Not a form-data request');
      }
    }
  ```

## 1.0.0

- Make `Multipart` constructor public.

## 0.1.0

- Initial version.
