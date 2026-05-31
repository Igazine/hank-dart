import 'Types.dart';
import 'Lexer.dart';
import 'ErrorRegistry.dart';

typedef MacroResolver = Expr Function(String macroPath);

class Parser {
  final List<Token> tokens;
  final String filename;
  final MacroResolver macroResolver;
  int pos = 0;

  Parser(this.tokens, this.filename, this.macroResolver);

  Expr parse() {
    _skipNewlines();
    List<Expr> stmts = [];

    // 1. Consume Macro Includes
    while (!_isEof() && _peek().type == TokenType.At) {
      stmts.add(_parseInclude());
      _skipNewlines();
    }

    if (_isEof()) throw _error(HankError.EmptyScript);

    // 2. Parse exactly ONE TaskDef (FuncDef or Block)
    Expr mainTask;
    if (_peek().type == TokenType.LParen && _isFuncDefStart()) {
      mainTask = _parseFuncDef();
    } else if (_peek().type == TokenType.LBrace) {
      mainTask = _parseBlock();
    } else {
      throw _error(HankError.ExpectedMainTask);
    }
    stmts.add(mainTask);

    // 3. Assert EOF
    _skipNewlines();
    if (!_isEof()) {
      throw _error(HankError.UnexpectedCodeOutsideMainTask);
    }

    if (stmts.length == 1) return stmts[0];
    return BlockExpr(stmts, _getTd(stmts[0]));
  }

  TokenData _getTd(Expr expr) => expr.td;

  Expr _parseStatement() {
    _skipNewlines();
    Token t = _peek();

    if (t.type == TokenType.Question) {
      return _parseFlowControl();
    }

    if (t.type == TokenType.At) {
      return _parseInclude();
    }

    if (t.type == TokenType.Caret) {
      return _parseReturn();
    }

    Expr expr = _parseExpression();
    _skipNewlines();
    return expr;
  }

  Expr _parseFlowControl() {
    TokenData td = _consume(TokenType.Question);
    
    Expr condition;
    if (_peek().type == TokenType.LParen) {
      _consume(TokenType.LParen);
      condition = _parseExpression();
      _consume(TokenType.RParen);
    } else {
      condition = _parseExpression();
    }

    Expr success = _parseBlock();

    Expr? fallback;
    Expr? rescue;
    String? catchVar;

    int savedPos = pos;
    _skipNewlines();
    if (_peek().type == TokenType.Colon) {
      _consume(TokenType.Colon);
      fallback = _parseBlock();
      savedPos = pos;
      _skipNewlines();
    } else {
      pos = savedPos;
    }

    if (_peek().type == TokenType.Rescue) {
      _consume(TokenType.Rescue);
      if (_peek().type == TokenType.LParen) {
        _consume(TokenType.LParen);
        catchVar = _consumeIdentifier();
        _consume(TokenType.RParen);
      }
      rescue = _parseBlock();
    } else {
      pos = savedPos;
    }

    return FlowControlExpr(
      condition: condition,
      success: success,
      fallback: fallback,
      rescue: rescue,
      catchVar: catchVar,
      td: td,
    );
  }

  Expr _parseInclude() {
    TokenData td = _consume(TokenType.At);
    Token t = _peek();
    String rawPath;
    if (t.type == TokenType.String) {
      rawPath = _parseStringLiteral(t.literal);
      _consume(TokenType.String);
    } else {
      throw _error(HankError.MacroRequiresString);
    }

    Expr taskAst = macroResolver(rawPath);
    String taskName = rawPath.split('/').last.split('.').first;

    return AssignExpr(taskName, taskAst, td);
  }

  Expr _parseExpression() {
    return _parseAssignment();
  }

  Expr _parseAssignment() {
    Expr expr = _parsePrimary();

    if (_peek().type == TokenType.Assign) {
      if (expr is IdentExpr && !expr.isCore) {
        TokenData td = _consume(TokenType.Assign);
        Expr val = _parseExpression();
        return AssignExpr(expr.name, val, td);
      } else {
        throw _error(HankError.InvalidAssignmentTarget);
      }
    }

    return expr;
  }

  Expr _parsePrimary() {
    Token t = _peek();
    TokenData td = t.td;

    Expr expr;
    switch (t.type) {
      case TokenType.At:
        expr = _parseInclude();
        break;
      case TokenType.Number:
        expr = LiteralExpr(Value.number(double.parse(t.literal)), td);
        _consume(TokenType.Number);
        break;
      case TokenType.String:
        expr = LiteralExpr(Value.string(_parseStringLiteral(t.literal)), td);
        _consume(TokenType.String);
        break;
      case TokenType.Identifier:
        expr = IdentExpr(t.literal, false, td);
        _consume(TokenType.Identifier);
        break;
      case TokenType.Hash:
        _consume(TokenType.Hash);
        String name = _consumeIdentifier();
        expr = IdentExpr(name, true, td);
        break;
      case TokenType.LParen:
        if (_isFuncDefStart()) {
          expr = _parseFuncDef();
        } else {
          _consume(TokenType.LParen);
          expr = _parseExpression();
          _consume(TokenType.RParen);
        }
        break;
      case TokenType.LBracket:
        expr = _parseCollectionLiteral();
        break;
      case TokenType.LBrace:
        // Ambiguity Protection: Standalone {} blocks are not allowed in v1.5.0.
        // They must be part of a task/function definition.
        if (_isFuncDefStart()) {
          expr = _parseFuncDef();
        } else {
          throw _error(HankError.UnexpectedToken, [t.type, t.literal]);
        }
        break;
      case TokenType.Caret:
        expr = _parseReturn();
        break;
      case TokenType.Not:
        _consume(TokenType.Not);
        expr = UnOpExpr('!', _parsePrimary(), td);
        break;
      case TokenType.Error:
        throw _error(HankError.UnexpectedCharacter, [t.literal]);
      default:
        throw _error(HankError.UnexpectedToken, [t.type, t.literal]);
    }

    return _finishPrimary(expr);
  }

  Expr _finishPrimary(Expr expr) {
    while (true) {
      Token t = _peek();
      if (t.type == TokenType.LParen) {
        expr = FuncCallExpr(expr, _parseArgList(), t.td);
      } else {
        break;
      }
    }
    return expr;
  }

  bool _isFuncDefStart() {
    int p = pos;
    if (tokens[p].type != TokenType.LParen) return false;
    p++;
    int depth = 1;
    while (p < tokens.length && depth > 0) {
      if (tokens[p].type == TokenType.LParen) depth++;
      if (tokens[p].type == TokenType.RParen) depth--;
      p++;
    }
    while (p < tokens.length && tokens[p].type == TokenType.Newline) p++;
    return p < tokens.length && tokens[p].type == TokenType.LBrace;
  }

  Expr _parseFuncDef() {
    TokenData td = _peek().td;
    _consume(TokenType.LParen);
    List<Param> params = [];
    if (_peek().type != TokenType.RParen) {
      params.add(_parseParam());
      while (_peek().type == TokenType.Comma) {
        _consume(TokenType.Comma);
        params.add(_parseParam());
      }
    }
    _consume(TokenType.RParen);
    Expr body = _parseBlock();
    return FuncDefExpr(params, body, td);
  }

  Param _parseParam() {
    bool isOptional = false;
    if (_peek().type == TokenType.Question) {
      _consume(TokenType.Question);
      isOptional = true;
    }
    String name = _consumeIdentifier();
    Expr? defaultValue;
    if (_peek().type == TokenType.Assign) {
      _consume(TokenType.Assign);
      defaultValue = _parseExpression();
      isOptional = true;
    }
    return Param(name: name, isOptional: isOptional, defaultValue: defaultValue);
  }

  Expr _parseBlock() {
    TokenData td = _consume(TokenType.LBrace);
    List<Expr> stmts = [];
    while (_peek().type != TokenType.RBrace && !_isEof()) {
      _skipNewlines();
      if (_peek().type == TokenType.RBrace) break;
      stmts.add(_parseStatement());
    }
    _consume(TokenType.RBrace);
    return BlockExpr(stmts, td);
  }

  Expr _parseCollectionLiteral() {
    TokenData td = _consume(TokenType.LBracket);
    _skipNewlines();

    // 1. Handle [:]
    if (_peek().type == TokenType.Colon) {
      _consume(TokenType.Colon);
      _consume(TokenType.RBracket);
      return MapExpr({}, td);
    }

    // 2. Handle []
    if (_peek().type == TokenType.RBracket) {
      _consume(TokenType.RBracket);
      return ArrayExpr([], td);
    }

    // 3. Parse first element
    Expr first = _parseExpression();
    _skipNewlines();

    if (_peek().type == TokenType.Colon) {
      // This is a Map
      _consume(TokenType.Colon);
      Expr val = _parseExpression();
      Map<String, Expr> fields = {};
      fields[_getStaticKey(first)] = val;

      while (true) {
        _skipNewlines();
        if (_peek().type == TokenType.Comma) {
          _consume(TokenType.Comma);
          _skipNewlines();
          if (_peek().type == TokenType.RBracket) break;
          Expr keyExpr = _parseExpression();
          _consume(TokenType.Colon);
          Expr valExpr = _parseExpression();
          fields[_getStaticKey(keyExpr)] = valExpr;
        } else {
          break;
        }
      }
      _consume(TokenType.RBracket);
      return MapExpr(fields, td);
    } else {
      // This is an Array
      List<Expr> items = [first];
      while (true) {
        _skipNewlines();
        if (_peek().type == TokenType.Comma) {
          _consume(TokenType.Comma);
          _skipNewlines();
          if (_peek().type == TokenType.RBracket) break;
          items.add(_parseExpression());
        } else {
          break;
        }
      }
      _consume(TokenType.RBracket);
      return ArrayExpr(items, td);
    }
  }

  String _getStaticKey(Expr e) {
    if (e is LiteralExpr && e.value.type == ValueType.String) return e.value.value;
    if (e is IdentExpr && !e.isCore) return e.name;
    throw _error(HankError.ExpectedIdentifier, [_peek().type]);
  }

  List<Expr> _parseArgList() {
    _consume(TokenType.LParen);
    List<Expr> args = [];
    _skipNewlines();
    if (_peek().type != TokenType.RParen) {
      args.add(_parseExpression());
      while (true) {
        _skipNewlines();
        if (_peek().type == TokenType.Comma) {
          _consume(TokenType.Comma);
          _skipNewlines();
          args.add(_parseExpression());
        } else {
          break;
        }
      }
    }
    _skipNewlines();
    _consume(TokenType.RParen);
    return args;
  }

  Expr _parseReturn() {
    TokenData td = _consume(TokenType.Caret);
    Expr val;
    if (!_isEof() && ![TokenType.Newline, TokenType.RBrace, TokenType.RBracket, TokenType.Comma, TokenType.RParen].contains(_peek().type)) {
       val = _parseExpression();
    } else {
       val = LiteralExpr(Value.voidVal(), td);
    }
    return UnOpExpr('^', val, td);
  }

  String _parseStringLiteral(String lit) {
    if (lit.length < 2) return lit;
    return lit.substring(1, lit.length - 1)
        .replaceAll('\\n', '\n')
        .replaceAll('\\r', '\r')
        .replaceAll('\\t', '\t')
        .replaceAll('\\"', '"')
        .replaceAll("\\'", "'");
  }

  String _consumeIdentifier() {
    Token t = _peek();
    if (t.type == TokenType.Identifier) {
      _consume(TokenType.Identifier);
      return t.literal;
    }
    throw _error(HankError.ExpectedIdentifier, [t.type]);
  }

  TokenData _consume(TokenType type) {
    Token t = _peek();
    if (t.type == type) {
      pos++;
      return t.td;
    }
    throw _error(HankError.UnexpectedToken, [type, t.type]);
  }

  Token _peek() => tokens[pos];

  void _skipNewlines() {
    while (pos < tokens.length && tokens[pos].type == TokenType.Newline) {
      pos++;
    }
  }

  bool _isEof() => pos >= tokens.length || tokens[pos].type == TokenType.EOF;

  Exception _error(HankError code, [List<dynamic>? args]) {
    TokenData td = _peek().td;
    return HankErrorRegistry.create(code, args, filename, td.line, td.column, td.lineText);
  }
}
