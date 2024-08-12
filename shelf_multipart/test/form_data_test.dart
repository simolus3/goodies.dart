import 'dart:async';

import 'package:shelf/shelf.dart';
import 'package:shelf_multipart/shelf_multipart.dart';
import 'package:test/test.dart';

final _uri = Uri.parse('http://localhost/');

void main() {
  group('checks whether a request has form data', () {
    const cases = {
      null: isNull,
      'multipart/mixed': isNull,
      'multipart/form-data': isNull,
      'multipart/form-data; boundary=end': isNotNull,
      'application/json': isNull,
    };

    cases.forEach((header, expected) {
      test('with content-type: $header is $expected', () {
        final request = Request('POST', _uri, headers: {
          if (header != null) 'content-type': header,
        });

        expect(request.formData(), expected);
      });
    });
  });

  test('can access form data', () async {
    final request = Request(
      'POST',
      _uri,
      headers: {'content-type': 'multipart/form-data; boundary=end'},
      body: '\r\n--end\r\n'
          'content-disposition: form-data; name="f1" \r\n'
          '\r\n'
          'Value of the first field'
          '\r\n--end\r\n'
          '\r\n'
          'Weird entry without headers\r\n'
          '\r\n--end\r\n'
          'content-disposition: form-data; name="f2"; filename="x.png"\r\n'
          '\r\n'
          'Value of the second field!'
          '\r\n--end--\r\n',
    );

    final reader = StreamIterator(FormDataRequest.of(request)!.formData);
    expect(await reader.moveNext(), isTrue);

    var form = reader.current;

    expect(form.name, 'f1');
    expect(form.filename, isNull);
    expect(await form.part.readString(), 'Value of the first field');

    expect(await reader.moveNext(), isTrue);
    form = reader.current;
    expect(form.name, 'f2');
    expect(form.filename, 'x.png');
    expect(await form.part.readString(), 'Value of the second field!');

    expect(await reader.moveNext(), isFalse);
  });
}
