Embeddable code snippets derived from source files for `jaspr_content`, with
support for semantic tokens.

## Motivation

When writing documentation sites for larger projects, a common challenge is
ensuring code snippets on the site are up-to-date. When code snippets are
directly embedded in Markdown, this is quite hard to do: Every time an API is
changed, you'd have to remember to update relevant snippets.

For sites built with `jaspr_content`, this package offers an alternative: You
write Dart snippets as regular `.dart` files into `lib/`, meaning that they'd
get analyzed and that you can write tests ensuring they do what they're
supposed to do.
Then, you use a custom component provided by this package to show highlighted
code.

This package can generate excerpts from snippets for all languages and leave
the user responsible for highlighting code. However, it also comes with
dedicated support for the following languages:

1. __Dart__: Source snippets are resolved to add support for [semantic tokens](https://github.com/dart-lang/sdk/blob/484c0b85b36c4aa957165d8d7137589df199a683/pkg/analysis_server/doc/implementation/semantic_highlighting.md#L4),
  resulting in improved syntax highlighting.
  Additionally, the package can generate hyperlinks to generated `dart doc`
  pages for your projects.
2. __SQL__: Uses the `sqlparser` package for accurate syntax highlighting.

## Features

TODO: List what your package can do. Maybe include images, gifs, or videos.

## Getting started

TODO: List prerequisites and provide or point to information on how to
start using the package.

## Usage

TODO: Include short and useful examples for package users. Add longer examples
to `/example` folder. 

```dart
const like = 'sample';
```

## Additional information

TODO: Tell users more about the package: where to find more information, how to 
contribute to the package, how to file issues, what response they can expect 
from the package authors, and more.
