/// Support for handling multipart requests in a shelf server.
///
/// The [ReadMultipartRequest] extensions can be used to check whether a request
/// is a multipart request and to extract the individual parts.
library shelf_multipart;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:shelf/shelf.dart';
import 'package:string_scanner/string_scanner.dart';

/// A multipart request.
///
/// Multipart requests contain multiple request bodies, each with their own
/// additional headers. To check whether a request is a multipart request, call
/// [Multipart.of] and check for a non-null return value.
/// To iterate over bodies, use [MultipartRequest.parts].
///
/// The individual parts can be accessed through the [parts] stream:
///
/// ```dart
/// Future<void> handleMultipart(Request request) {
///   if (request.multipart() case var multipart?) {
///     await for (final part in multipart.parts) {
///       print('Has part: ${part.headers}, body: ${await part.readString()}');
///     }
///   }
/// }
/// ```
extension type MultipartRequest._((Request, MediaType, String) _data) {
  /// Checks whether [request] has a multipart boundary and, if so, wraps the
  /// request in a [MultipartRequest] type allowing the individual parts to be
  /// accessed.
  ///
  /// Requests are considered to have a multipart body if they have a
  /// `Content-Type` header with a `multipart` type and a valid `boundary`
  /// parameter as defined by section 5.1.1 of RFC 2046.
  static MultipartRequest? of(Request request) {
    var boundary = _extractMultipartBoundary(request);
    if (boundary == null) {
      return null;
    } else {
      return MultipartRequest._((request, boundary.$1, boundary.$2));
    }
  }

  /// The underlying request with a multipart body.
  Request get request => _data.$1;

  /// Return the full media type of the original [request], typically something
  /// like `multipart/mixed; end=$end`.
  MediaType get mediaType => _data.$2;

  /// The boundary used to separate parts as part of the body.
  String get boundary => _data.$3;

  /// Reads parts of this multipart request.
  ///
  /// Each part is represented as a [MimeMultipart], which implements the
  /// [Stream] interface to emit chunks of data.
  /// Headers of a part are available through [MimeMultipart.headers].
  ///
  /// Parts can be processed by listening to this stream, as shown in this
  /// example:
  ///
  /// ```dart
  /// await for (final part in request.parts) {
  ///   final headers = part.headers;
  ///   final content = utf8.decoder.bind(part).first;
  /// }
  /// ```
  ///
  /// Listening to this stream will [read] this request, which may only be done
  /// once.
  ///
  /// The stream will emit a [MimeMultipartException] if the request does not
  /// contain a well-formed multipart body.
  Stream<Multipart> get parts {
    return MimeMultipartTransformer(boundary)
        .bind(request.read())
        .map((part) => Multipart(request, part));
  }

  /// Extracts the `boundary` parameter from the content-type header, if this is
  /// a multipart request.
  static (MediaType, String)? _extractMultipartBoundary(Request request) {
    var header = request.headers['Content-Type'];
    if (header == null) {
      return null;
    }

    final contentType = MediaType.parse(header);
    if (contentType.type != 'multipart') return null;

    var boundary = contentType.parameters['boundary'];
    if (boundary == null) {
      return null;
    }

    return (contentType, boundary);
  }
}

/// A multipart request containing form data.
///
/// The submitted form fields can be accessed through the [formData] stream:
///
/// ```dart
/// Future<void> readForm(Request request) {
///   if (request.formData() case var form?) {
///     await for (final data in form.formData) {
///       print(''${formData.name}: ${await formData.part.readString()}'');
///     }
///   }
/// }
/// ```
extension type FormDataRequest._(MultipartRequest _)
    implements MultipartRequest {
  static FormDataRequest? of(Request request) {
    var multipart = MultipartRequest.of(request);
    if (multipart == null || multipart.mediaType.subtype != 'form-data') {
      return null;
    }

    return FormDataRequest._(multipart);
  }

  /// Reads invididual form data elements from this request.
  Stream<FormData> get formData {
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

/// Extensions that call [MultipartRequest.of] and [FormDataRequest.of] as an
/// extension on [Request].
extension MultipartFromRequest on Request {
  /// Calls [MultipartRequest.of], returning a multipart representation of this
  /// request if it has the multipart content type.
  ///
  /// See [MultipartRequest] for details.
  MultipartRequest? multipart() {
    return MultipartRequest.of(this);
  }

  /// Calls [FormDataRequest.of], returning a form-data representation of this
  /// request if it has the multipart content type.
  ///
  /// See [FormDataRequest] for details.
  FormDataRequest? formData() {
    return FormDataRequest.of(this);
  }
}

/// An entry in a multipart request.
class Multipart extends MimeMultipart {
  final Request _originalRequest;
  final MimeMultipart _inner;

  @override
  final Map<String, String> headers;

  late final MediaType? _contentType = _parseContentType();

  Encoding? get _encoding {
    var contentType = _contentType;
    if (contentType == null) return null;
    if (!contentType.parameters.containsKey('charset')) return null;
    return Encoding.getByName(contentType.parameters['charset']);
  }

  Multipart(this._originalRequest, this._inner)
      : headers = CaseInsensitiveMap.from(_inner.headers);

  MediaType? _parseContentType() {
    final value = headers['content-type'];
    if (value == null) return null;

    return MediaType.parse(value);
  }

  /// Reads the content of this subpart as a single [Uint8List].
  Future<Uint8List> readBytes() async {
    final builder = BytesBuilder();
    await forEach(builder.add);
    return builder.takeBytes();
  }

  /// Reads the content of this subpart as a string.
  ///
  /// The optional [encoding] parameter can be used to override the encoding
  /// used. By default, the `content-type` header of this part will be used,
  /// with a fallback to the `content-type` of the surrounding request and
  /// another fallback to [utf8] if everything else fails.
  Future<String> readString([Encoding? encoding]) {
    encoding ??= _encoding ?? _originalRequest.encoding ?? utf8;
    return encoding.decodeStream(this);
  }

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> data)? onData,
      {void Function()? onDone, Function? onError, bool? cancelOnError}) {
    return _inner.listen(onData,
        onDone: onDone, onError: onError, cancelOnError: cancelOnError);
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
