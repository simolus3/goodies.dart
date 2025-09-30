// Copied from sdk/third_party/pkg/language_server_protocol/lib/protocol_generated.dart

class SemanticTokenTypes {
  static const class_ = SemanticTokenTypes('class');
  static const comment = SemanticTokenTypes('comment');

  /// @since 3.17.0
  static const decorator = SemanticTokenTypes('decorator');

  static const enum_ = SemanticTokenTypes('enum');
  static const enumMember = SemanticTokenTypes('enumMember');
  static const event = SemanticTokenTypes('event');
  static const function = SemanticTokenTypes('function');
  static const interface = SemanticTokenTypes('interface');
  static const keyword = SemanticTokenTypes('keyword');
  static const macro = SemanticTokenTypes('macro');
  static const method = SemanticTokenTypes('method');
  static const modifier = SemanticTokenTypes('modifier');
  static const namespace = SemanticTokenTypes('namespace');
  static const number = SemanticTokenTypes('number');
  static const operator = SemanticTokenTypes('operator');
  static const parameter = SemanticTokenTypes('parameter');
  static const property = SemanticTokenTypes('property');
  static const regexp = SemanticTokenTypes('regexp');
  static const string = SemanticTokenTypes('string');
  static const struct = SemanticTokenTypes('struct');

  /// Represents a generic type. Acts as a fallback for types which can't be
  /// mapped to a specific type like class or enum.
  static const type = SemanticTokenTypes('type');
  static const typeParameter = SemanticTokenTypes('typeParameter');
  static const variable = SemanticTokenTypes('variable');
  final String _value;
  const SemanticTokenTypes(this._value);
  const SemanticTokenTypes.fromJson(this._value);
  @override
  int get hashCode => _value.hashCode;

  @override
  bool operator ==(Object other) =>
      other is SemanticTokenTypes && other._value == _value;

  String toJson() => _value;

  @override
  String toString() => _value.toString();
}

/// A set of predefined token modifiers. This set is not fixed an clients can
/// specify additional token types via the corresponding client capabilities.
///
/// @since 3.16.0
class SemanticTokenModifiers {
  static const abstract = SemanticTokenModifiers('abstract');
  static const async = SemanticTokenModifiers('async');

  static const declaration = SemanticTokenModifiers('declaration');

  static const defaultLibrary = SemanticTokenModifiers('defaultLibrary');
  static const definition = SemanticTokenModifiers('definition');
  static const deprecated = SemanticTokenModifiers('deprecated');
  static const documentation = SemanticTokenModifiers('documentation');
  static const modification = SemanticTokenModifiers('modification');
  static const readonly = SemanticTokenModifiers('readonly');
  static const static = SemanticTokenModifiers('static');
  final String _value;
  const SemanticTokenModifiers(this._value);
  const SemanticTokenModifiers.fromJson(this._value);
  @override
  int get hashCode => _value.hashCode;

  @override
  bool operator ==(Object other) =>
      other is SemanticTokenModifiers && other._value == _value;

  String toJson() => _value;

  @override
  String toString() => _value.toString();
}

abstract final class CustomSemanticTokenModifiers {
  /// A modifier applied to the identifier following the `@` annotation token to
  /// allow users to color it differently (for example in the same way as `@`).
  static const annotation = SemanticTokenModifiers('annotation');

  /// A modifier applied to control keywords like if/for/etc. so they can be
  /// colored differently to other keywords (void, import, etc), matching the
  /// original Dart textmate grammar.
  /// https://github.com/dart-lang/dart-syntax-highlight/blob/84a8e84f79bc917ebd959a4587349c865dc945e0/grammars/dart.json#L244-L261
  static const control = SemanticTokenModifiers('control');

  /// A modifier applied to the identifier for an import prefix.
  static const importPrefix = SemanticTokenModifiers('importPrefix');

  /// A modifier applied to parameter references to indicate they are the name/label
  /// to allow theming them differently to the values.
  ///
  /// This is different to [CustomSemanticTokenTypes.label] which is for labels
  /// as used in loops/switch statements.
  ///
  /// In the code `foo({String a}) => foo(a: a)` the a's will be differentiated
  /// as:
  /// - parameter.declaration
  /// - parameter.label
  /// - parameter
  static const label = SemanticTokenModifiers('label');

  /// A modifier applied to constructors to allow coloring them differently
  /// to class names that are not constructors.
  static const constructor = SemanticTokenModifiers('constructor');

  /// A modifier applied to wildcards.
  static const wildcard = SemanticTokenModifiers('wildcard');

  /// A modifier applied to escape characters within a string to allow coloring
  /// them differently.
  static const escape = SemanticTokenModifiers('escape');

  /// A modifier applied to an interpolation expression in a string to allow
  /// coloring it differently to the literal parts of the string.
  ///
  /// Many tokens within interpolation expressions will get their own semantic
  /// tokens so this is mainly to account for the surrounding `${}` and
  /// tokens like parens and operators that may not get their own.
  ///
  /// This is useful for editors that supply their own basic coloring initially
  /// (for faster coloring) and then layer semantic tokens over the top. Without
  /// some marker for interpolation expressions, all otherwise-uncolored parts
  /// of the expression would show through the simple-colorings "string" colors.
  static const interpolation = SemanticTokenModifiers('interpolation');

  /// A modifier applied to instance field/getter/setter/method references and
  /// declarations to distinguish them from top-levels.
  static const instance = SemanticTokenModifiers('instance');

  /// A modifier applied to the void keyword to allow users to color it
  /// differently (for example as a type).
  static const void_ = SemanticTokenModifiers('void');

  /// All custom semantic token modifiers, used to populate the LSP Legend.
  ///
  /// The legend must include all used modifiers. Modifiers used in the
  /// HighlightRegion mappings will be automatically included, but should still
  /// be listed here in case they are removed from mappings in the future.
  static const values = [
    annotation,
    control,
    importPrefix,
    instance,
    label,
    constructor,
    escape,
    interpolation,
    void_,
    wildcard,
  ];
}

abstract final class CustomSemanticTokenTypes {
  static const annotation = SemanticTokenTypes('annotation');
  static const boolean = SemanticTokenTypes('boolean');

  /// A token type for labels.
  ///
  /// This is different to [CustomSemanticTokenModifiers.label] which is for
  /// parameter name labels.
  ///
  /// 'label' is listed as a standard VS Code token type at
  /// https://code.visualstudio.com/api/language-extensions/semantic-highlight-guide
  /// and therefore may be used by theme authors, but it's currently not defined
  /// by LSP (and therefore missing from the code-generated SemanticTokenTypes)
  /// so we have to define it here.
  ///
  /// This can be removed once
  /// https://github.com/microsoft/language-server-protocol/issues/2137 is
  /// resolved.
  static const label = SemanticTokenTypes('label');

  /// A placeholder token type for basic source code that is not usually colored.
  ///
  /// This is used only where clients might otherwise provide their own coloring
  /// (for example coloring whole strings that may include interpolated code).
  ///
  /// Tokens using this type should generally also provide a custom
  /// [CustomSemanticTokenModifiers] to give the client more information about
  /// the reason for this token and allow specific coloring if desired.
  static const source = SemanticTokenTypes('source');

  /// All custom semantic token types, used to populate the LSP Legend which must
  /// include all used types.
  static const values = [annotation, boolean, label, source];
}
