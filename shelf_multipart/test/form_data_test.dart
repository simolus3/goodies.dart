import 'dart:async';

import 'package:shelf_multipart/form_data.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

final _uri = Uri.parse('http://localhost/');

void main() {
  group('isMultipartForm', () {
    const cases = {
      null: false,
      'multipart/mixed': false,
      'multipart/form-data': true,
      'application/json': false,
    };

    cases.forEach((header, expected) {
      test('with content-type: $header is $expected', () {
        final request = Request('POST', _uri, headers: {
          if (header != null) 'content-type': header,
        });

        expect(request.isMultipartForm, expected);
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

    final reader = StreamIterator(request.multipartFormData);
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
