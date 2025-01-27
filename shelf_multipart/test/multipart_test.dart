import 'dart:convert';

import 'package:mime/mime.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_multipart/shelf_multipart.dart';
import 'package:test/test.dart';

final _uri = Uri.parse('http://localhost/');

void main() {
  group('multipart() returns', () {
    test('null for requests without a content-type header', () async {
      Response handler(Request r) => Response.ok(r.multipart().toString());
      final response = handler(Request('POST', _uri));

      expect(response.readAsString(), completion('null'));
    });

    test('false for Content-Type: multipart without boundary', () {
      expect(
        Request('GET', _uri, headers: {'Content-Type': 'multipart/mixed'})
            .multipart(),
        isNull,
      );
    });

    test('true for multipart headers', () {
      expect(
        Request('GET', _uri, headers: {
          'Content-Type': 'multipart/mixed; boundary=gc0p4Jq0M2Yt08j34c0p'
        }).multipart(),
        isNotNull,
      );
    });
  });

  test('can access part headers without case sensitivity', () async {
    Future<Response> handler(Request request) async {
      final multipart = request.multipart()!;

      final part = await multipart.parts.first;
      return Response.ok(part.headers['foo'].toString());
    }

    final response = await handler(Request(
      'POST',
      _uri,
      body: '\r\n--end\r\n'
          'FOO: header value\r\n'
          '\r\n'
          'content\r\n'
          '--end--',
      headers: {
        'Content-Type': 'multipart/mixed; boundary=end',
      },
    ));

    expect(response.readAsString(), completion('header value'));
  });

  test('can access multipart bodies', () async {
    Future<Response> handler(Request request) async {
      final result = StringBuffer();
      await for (final part in MultipartRequest.of(request)!.parts) {
        await utf8.decoder.bind(part).forEach(result.write);
      }

      return Response.ok(result.toString());
    }

    final response = await handler(Request(
      'POST',
      _uri,
      body: '\r\n--end\r\n'
          '\r\n'
          'first part, no line break\r\n'
          '--end\r\n'
          '\r\n'
          'second part, with line break\n'
          '\r\n'
          '--end--\r\n',
      headers: {
        'Content-Type': 'multipart/mixed; boundary=end',
      },
    ));

    expect(
      response.readAsString(),
      completion('first part, no line breaksecond part, with line break\n'),
    );
  });

  test('can read body with readBytes()', () async {
    Future<Response> handler(Request request) async {
      var totalLength = 0;
      await for (final part in MultipartRequest.of(request)!.parts) {
        totalLength += (await part.readBytes()).length;
      }

      return Response.ok(totalLength.toString());
    }

    final response = await handler(Request(
      'POST',
      _uri,
      body: '\r\n--end\r\n'
          '\r\n'
          'first part here\r\n'
          '--end--\r\n',
      headers: {
        'Content-Type': 'multipart/mixed; boundary=end',
      },
    ));

    expect(
      response.readAsString(),
      completion('15'),
    );
  });

  test('can read body with readString()', () async {
    Future<Response> handler(Request request) async {
      final result = StringBuffer();
      await for (final part in MultipartRequest.of(request)!.parts) {
        result.write(await part.readString());
      }

      return Response.ok(result.toString());
    }

    final response = await handler(Request(
      'POST',
      _uri,
      body: '\r\n--end\r\n'
          '\r\n'
          'first part, no line break\r\n'
          '--end\r\n'
          '\r\n'
          'second part, with line break\n'
          '\r\n'
          '--end--\r\n',
      headers: {
        'Content-Type': 'multipart/mixed; boundary=end',
      },
    ));

    expect(
      response.readAsString(),
      completion('first part, no line breaksecond part, with line break\n'),
    );
  });

  test('throws when reading an ill-formed multipart body', () async {
    Future<Response> handler(Request request) async {
      await for (final _ in MultipartRequest.of(request)!.parts) {}

      return Response.ok('ok');
    }

    final request = Request(
      'POST',
      _uri,
      body: '\r\n--end\r\n'
          '\r\n'
          'missing -- from end\r\n'
          '--end\r\n',
      headers: {
        'Content-Type': 'multipart/mixed; boundary=end',
      },
    );

    expect(handler(request), throwsA(isA<MimeMultipartException>()));
  });

  test('can access content type', () async {
    Future<Response> handler(Request request) async =>
        Response.ok(request.multipart()?.mediaType.subtype);

    final response = await handler(Request(
      'POST',
      _uri,
      body: '\r\n--end\r\n'
          '\r\n',
      headers: {
        'Content-Type': 'multipart/alternative; boundary=end',
      },
    ));

    expect(response.readAsString(), completion('alternative'));
  });
}
