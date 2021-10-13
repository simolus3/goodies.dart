/// Wrapper around the `multipart` library to extract form data from a request.
library form_data;

import 'package:http_parser/http_parser.dart';
import 'package:shelf/shelf.dart';
import 'package:string_scanner/string_scanner.dart';

import 'multipart.dart';

extension ReadFormData on Request {
  /// Whether this request has a multipart form body.
  bool get isMultipartForm {
    final rawContentType = headers['Content-Type'];
    if (rawContentType == null) return false;

    final type = MediaType.parse(rawContentType);
    return type.type == 'multipart' && type.subtype == 'form-data';
  }

  /// Reads invididual form data elements from this request.
  Stream<FormData> get multipartFormData {
    return parts
        .map<FormData?>((part) {
          final rawDisposition = part.headers['content-disposition'];
          if (rawDisposition == null) return null;

          final formDataParams =
              _parseFormDataContentDisposition(rawDisposition);
          if (formDataParams == null) return null;

          final name = formDataParams['name'];
          if (name == null) return null;

          return FormData._(name, formDataParams['filename'], part);
        })
        .where((data) => data != null)
        .cast();
  }
}

/// A [Multipart] subpart with a parsed [name] and [filename] values read from
/// its `content-disposition` header.
class FormData {
  /// The name of this form data element.
  ///
  /// Names are usually unique, but this is not verified by this package.
  final String name;

  /// An optional name describing the name of the file being uploaded.
  final String? filename;

  final Multipart part;

  FormData._(this.name, this.filename, this.part);
}

final _token = RegExp(r'[^()<>@,;:"\\/[\]?={} \t\x00-\x1F\x7F]+');
final _whitespace = RegExp(r'(?:(?:\r\n)?[ \t]+)*');
final _quotedString = RegExp(r'"(?:[^"\x00-\x1F\x7F]|\\.)*"');
final _quotedPair = RegExp(r'\\(.)');

/// Parses a `content-disposition: form-data; arg1="val1"; ...` header.
Map<String, String>? _parseFormDataContentDisposition(String header) {
  final scanner = StringScanner(header);

  scanner
    ..scan(_whitespace)
    ..expect(_token);
  if (scanner.lastMatch![0] != 'form-data') return null;

  final params = <String, String>{};

  while (scanner.scan(';')) {
    scanner
      ..scan(_whitespace)
      ..scan(_token);
    final key = scanner.lastMatch![0]!;
    scanner.expect('=');

    String value;
    if (scanner.scan(_token)) {
      value = scanner.lastMatch![0]!;
    } else {
      scanner.expect(_quotedString, name: 'quoted string');
      final string = scanner.lastMatch![0]!;

      value = string
          .substring(1, string.length - 1)
          .replaceAllMapped(_quotedPair, (match) => match[1]!);
    }

    scanner.scan(_whitespace);
    params[key] = value;
  }

  scanner.expectDone();
  return params;
}
