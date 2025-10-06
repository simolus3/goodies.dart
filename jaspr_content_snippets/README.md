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

A rendered demo of this package is available on [my website](https://www.simonbinder.eu/posts/built_snippets/).

## Features

This package can generate excerpts from snippets for all languages and leave
the user responsible for highlighting code. However, it also comes with
dedicated support for the following languages:

1. __Dart__: Source snippets are resolved to add support for [semantic tokens](https://github.com/dart-lang/sdk/blob/484c0b85b36c4aa957165d8d7137589df199a683/pkg/analysis_server/doc/implementation/semantic_highlighting.md#L4),
  resulting in improved syntax highlighting.
  Additionally, the package can generate hyperlinks to generated `dart doc`
  pages for your projects.
2. __SQL__: Uses the `sqlparser` package for accurate syntax highlighting.

Note that this is a fairly low-level package designed for use in drift's
documentation website. Feedback and PRs to make it more generally useful are
definitely welcome though.

## Getting started

To get started, apply the `jaspr_content_snippets` builder to a target
containing snippets you want to extract.
For instance, if you have snippets in `lib/src/snippets/`, you could write a
`build.yaml` with:

```yaml
targets:
  $default:
    builders:
      jaspr_content_snippets:
        enabled: true
        options:
          process_without_directives: true
        generate_for:
          - lib/src/snippets/**
```

By default, the builder will only process files that have at least one
`#docregion` comment in them (see [usage](#usage)).
The `process_without_directives` disables this rule.

## Usage

This package exports three steps, some of which are optional:

1. Mark some packages as targets for links when their APIs are used in
   snippets.
2. Enable the snippets builder to extract snippets.
3. Use a jaspr component to render snippets.

These steps are fairly modular, so you can replace them with your own logic
where that makes sense.

### Linking APIs

To link Dart identifiers and import URIs to their `dart doc` pages, configure
the `jaspr_content_snippets:api_index` builder to include those packages. Since
that builder runs on all packages, it's easier to configure it with a
`global_options` entry in `build.yaml`:

```yaml
global_options:
  "jaspr_content_snippets:api_index":
    options:
      packages: ['your_package', 'another_one']
```

To link to SDK documentation (`api.dart.dev`), include the synthetic `$sdk` package
in that list.

### Extracting snippets

The snippets builder will, for each source file it's running on, generate a
`.snippet.json` encoding

1. Line ranges for `#docregion` and `#enddocregion` pairs.
2. If the language is known (SQL and Dart are built-in to this package), tokens
   encoded as `(offset, length)` keys with their semantic token identifier as
   specified in the LSP protocol.
3. Raw HTML consisting of `<span>`s for known tokens.

To generate the snippets, enable the builder:

```yaml
targets:
  $default:
    builders:
      jaspr_content_snippets:
        enabled: true
        options:
          process_without_directives: true
        generate_for:
          - lib/src/snippets/**
```

### Rendering snippets

Loading extracted snippets is somewhat tricky, since they're generated as
hidden build files.

This package offers the `jaspr_content_snippets:combiner` builder generating a
single `generated_snippets.dart` file encoding all snippets.
The target path of that file can be customized:

```yaml
targets:
  $default:
    builders:
      jaspr_content_snippets:combiner:
        options:
          path: lib/generated_snippets.dart
```

This file can then be used in a `jaspr_content` pipeline by registering it as a custom
component:

```dart
components: [
  // ...
  renderedSnippetComponent(snippets: generatedSnippets),
],
```

With that set up, you can use the `<Snippet href="/lib/src/your_snippet.dart" name="region" />`
tag to reference a snippet.

To render snippets you only have available as sources, use the `HighlightBlock` component
or the builtin `BetterCodeBlock` component which serves as a drop-in replacement for
`CodeBlock`:

```dart
import 'package:jaspr_content/jaspr_content.dart';
import 'package:jaspr_content_snippets/jaspr_content_snippets.dart';

final root = ContentApp.custom(
  // ...
  configResolver: PageConfig.all(
    // ...
    components: [
      BetterCodeBlock(),
      renderedSnippetComponent(snippets: generatedSnippets),
      // ...
    ],
  ),
);
```

## Additional information

This package embeds parts of `analysis_server` source code from the SDK.
That code imports internal `analyzer` and `_fe_analyzer_shared` APIs making this package somewhat
unstable.

### Styling

This package does not use `@style` annotations, nor does it ship with default styles for code
highlighting.
To get started quickly, consider adding this to your project's style:

```scss
@use "package:jaspr_content_snippets/common";
@use "package:jaspr_content_snippets/dracula" as dracula;

:root {
  @include dracula.light;
}

@media (prefers-color-scheme: dark) {
  :root {
    @include dracula.dark;
  }
}
```

### Updating analyzer sources

The `lib/src/highlight/dart/computer_highlights.dart` file is taken from the [Dart SDK](https://github.com/dart-lang/sdk/blob/main/pkg/analysis_server/lib/src/computer/computer_highlights.dart),
with some patches related to this package.

To update that file, copy it over and `git apply assets/computer_highlights.patch`.
