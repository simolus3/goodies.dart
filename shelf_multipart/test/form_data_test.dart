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

  test('rejects an unterminated quoted name without excessive backtracking',
      () async {
    final slashes = String.fromCharCodes(List.filled(44, 0x5c));
    final request = Request(
      'POST',
      _uri,
      headers: {'content-type': 'multipart/form-data; boundary=end'},
      body: '--end\r\n'
          'content-disposition: form-data; name="$slashes\r\n'
          '\r\n'
          'x\r\n'
          '--end--\r\n',
    );

    final watch = Stopwatch()..start();
    await expectLater(
      request.formData()!.formData.toList(),
      throwsA(isA<Exception>()),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('accepts an escaped quote in a form-data name', () async {
    final escape = String.fromCharCode(0x5c);
    final request = Request(
      'POST',
      _uri,
      headers: {'content-type': 'multipart/form-data; boundary=end'},
      body: '--end\r\n'
          'content-disposition: form-data; name="a$escape"b"\r\n'
          '\r\n'
          'x\r\n'
          '--end--\r\n',
    );

    var fields = 0;
    await for (final field in request.formData()!.formData) {
      expect(field.name, 'a"b');
      expect(await field.part.readString(), 'x');
      fields++;
    }
    expect(fields, 1);
  });

  group('rejects invalid content-disposition', () {
    const cases = {
      'unterminated quoted string': 'form-data; name="abc',
      'quoted string ending in escape': 'form-data; name="abc\\',
      'control character in quoted string': 'form-data; name="a\x01b"',
      'escaped control character': 'form-data; name="a\\\x01b"',
      'missing parameter name': 'form-data; ="x"',
    };

    cases.forEach((description, disposition) {
      test(description, () async {
        final request = Request(
          'POST',
          _uri,
          headers: {'content-type': 'multipart/form-data; boundary=end'},
          body: '--end\r\n'
              'content-disposition: $disposition\r\n'
              '\r\n'
              'x\r\n'
              '--end--\r\n',
        );

        await expectLater(
          request.formData()!.formData.toList(),
          throwsA(isA<FormatException>()),
        );
      });
    });
  });

  test('parses quoted strings with tabs and non-ASCII characters', () async {
    final request = Request(
      'POST',
      _uri,
      headers: {'content-type': 'multipart/form-data; boundary=end'},
      body: '--end\r\n'
          'content-disposition: form-data; name="a\tb"; filename="😀.txt"\r\n'
          '\r\n'
          'x\r\n'
          '--end--\r\n',
    );

    final fields = await request.formData()!.formData.toList();
    expect(fields, hasLength(1));
    expect(fields.single.name, 'a\tb');
    expect(fields.single.filename, '😀.txt');
  });
}
