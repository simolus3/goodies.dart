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

/// Extension methods to handle multipart requests.
///
/// To check whether a request contains multipart data, use [isMultipart].
/// Individual parts can the be red with [parts].
extension ReadMultipartRequest on Request {
  /// Whether this request has a multipart body.
  ///
  /// Requests are considered to have a multipart body if they have a
  /// `Content-Type` header with a `multipart` type and a valid `boundary`
  /// parameter as defined by section 5.1.1 of RFC 2046.
  bool get isMultipart => _extractMultipartBoundary() != null;

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
  /// Throws a [StateError] if this is not a multipart request (as reported
  /// through [isMultipart]). The stream will emit a [MimeMultipartException]
  /// if the request does not contain a well-formed multipart body.
  Stream<Multipart> get parts {
    final boundary = _extractMultipartBoundary();
    if (boundary == null) {
      throw StateError('Not a multipart request.');
    }

    return MimeMultipartTransformer(boundary)
        .bind(read())
        .map((part) => Multipart(this, part));
  }

  /// Extracts the `boundary` parameter from the content-type header, if this is
  /// a multipart request.
  String? _extractMultipartBoundary() {
    if (!headers.containsKey('Content-Type')) return null;

    final contentType = MediaType.parse(headers['Content-Type']!);
    if (contentType.type != 'multipart') return null;

    return contentType.parameters['boundary'];
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
