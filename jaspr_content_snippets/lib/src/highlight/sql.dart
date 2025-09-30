import 'package:build/build.dart';
import 'package:sqlparser/sqlparser.dart';

import 'highlighter.dart';
import 'token_type.dart';

class SqlHighlighter implements Highlighter {
  final AssetReader reader;

  SqlHighlighter(this.reader);

  @override
  Future<List<HighlightToken>> highlight(AssetId id) async {
    final engine = SqlEngine(
      EngineOptions(
        driftOptions: const DriftSqlOptions(),
        version: SqliteVersion.current,
      ),
    );

    final result = engine.parseDriftFile(await reader.readAsString(id));
    final tokens = <HighlightToken>[];
    void reportSql(
      SyntacticEntity? entity,
      SemanticTokenTypes type, {
      Set<SemanticTokenModifiers>? modifiers,
    }) {
      if (entity != null) {
        tokens.add(
          HighlightToken(
            offset: entity.firstPosition,
            length: entity.length,
            type: type,
            modifiers: modifiers,
          ),
        );
      }
    }

    _HighlightingVisitor().visit(result.rootNode, reportSql);

    for (final token in result.tokens) {
      if (token is KeywordToken && !token.isIdentifier) {
        reportSql(token, SemanticTokenTypes.keyword);
      } else if (token is CommentToken) {
        reportSql(token, SemanticTokenTypes.comment);
      } else if (token is StringLiteralToken) {
        reportSql(token, SemanticTokenTypes.string);
      }
    }

    return tokens;
  }
}

typedef TokenSink =
    void Function(
      SyntacticEntity?,
      SemanticTokenTypes, {
      Set<SemanticTokenModifiers>? modifiers,
    });

class _HighlightingVisitor extends RecursiveVisitor<TokenSink, void> {
  @override
  void visitCreateTriggerStatement(CreateTriggerStatement e, TokenSink arg) {
    arg(
      e.triggerNameToken,
      SemanticTokenTypes.class_,
      modifiers: {SemanticTokenModifiers.declaration},
    );
    visitChildren(e, arg);
  }

  @override
  void visitCreateViewStatement(CreateViewStatement e, TokenSink arg) {
    arg(
      e.viewNameToken,
      SemanticTokenTypes.class_,
      modifiers: {SemanticTokenModifiers.declaration},
    );
    visitChildren(e, arg);
  }

  @override
  void visitColumnDefinition(ColumnDefinition e, TokenSink arg) {
    arg(e.nameToken, SemanticTokenTypes.property);
    arg(e.typeNames?.toSingleEntity, SemanticTokenTypes.type);

    visitChildren(e, arg);
  }

  @override
  void visitNumericLiteral(NumericLiteral e, TokenSink arg) {
    arg(e, SemanticTokenTypes.number);
  }

  @override
  void visitDriftSpecificNode(DriftSpecificNode e, TokenSink arg) {
    if (e is DeclaredStatement) {
      final name = e.identifier;
      if (name is SimpleName) {
        arg(
          name.identifier,
          SemanticTokenTypes.function,
          modifiers: {SemanticTokenModifiers.declaration},
        );
      }
    }

    super.visitDriftSpecificNode(e, arg);
  }

  @override
  void visitReference(Reference e, TokenSink arg) {
    arg(e, SemanticTokenTypes.property);
  }

  @override
  void visitTableReference(TableReference e, TokenSink arg) {
    arg(e.tableNameToken, SemanticTokenTypes.class_);
  }

  @override
  void visitTableInducingStatement(TableInducingStatement e, TokenSink arg) {
    arg(
      e.tableNameToken,
      SemanticTokenTypes.class_,
      modifiers: {SemanticTokenModifiers.declaration},
    );

    if (e is CreateVirtualTableStatement) {
      arg(
        e.moduleNameToken,
        SemanticTokenTypes.function,
        modifiers: {SemanticTokenModifiers.static},
      );
    }

    visitChildren(e, arg);
  }

  @override
  void visitVariable(Variable e, TokenSink arg) {
    arg(e, SemanticTokenTypes.variable);
  }
}
