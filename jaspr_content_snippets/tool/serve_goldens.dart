import 'dart:io';

import 'package:jaspr/server.dart';
import 'package:shelf/shelf_io.dart';
import 'package:path/path.dart';

import '../test/goldens/generated_goldens.dart';

void main() {
  Jaspr.initializeApp();

  serve(
    (request) async {
      if (request.url.path == 'style.css') {
        return Response(
          200,
          body: _styles,
          headers: {'Content-Type': 'text/css'},
        );
      }

      if (request.url.path == '') {
        final body = await renderComponent(
          Document(
            body: ul([
              for (final file in generatedSnippets.keys)
                li([
                  a(href: url.relative(file, from: 'test/goldens/'), [
                    text(file),
                  ]),
                ]),
            ]),
          ),
        );
        return Response(
          body.statusCode,
          body: body.body,
          headers: body.headers,
        );
      }

      final goldens = generatedSnippets['test/goldens/${request.url.path}'];
      if (goldens == null) {
        return Response(404);
      }

      final body = await renderComponent(
        Document(
          head: [link(href: '/style.css', rel: 'stylesheet')],
          body: fragment([
            for (final MapEntry(:key, :value) in goldens.entries)
              div([
                h2([text(key)]),
                code([
                  pre([raw(value)]),
                ]),
                hr(),
              ]),
          ]),
        ),
      );
      return Response(body.statusCode, body: body.body, headers: body.headers);
    },
    InternetAddress.loopbackIPv4,
    8080,
  );

  print('Listening on http://localhost:8080/');
}

const _styles = '''
.keyword {
  color: blue;
}
.type {
  color: red;
}
.class {
  color: darkRed;
}
.property {
  color: darkGreen;
}
.function {
  color: yellowGreen;
}
.method {
  color: yellowGreen;
}
.variable {
  color: green;
}
.parameter {
  color: green;
}
.string {
  color: cyan;
}
.number {
  color: darkCyan;
}
.annotation {
  color: lightGreen;
}
.declaration {
  font-weight: bold;
}
''';
