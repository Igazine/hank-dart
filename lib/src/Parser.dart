import 'Types.dart';
import 'Lexer.dart';

class Parser {
  final List<Token> tokens;
  final String filename;
  final Map<String, String> macroMap;
  int pos = 0;

  Parser(this.tokens, this.filename, this.macroMap);

  Expr parse() {
    _skipNewlines();
    List<Expr> stmts = [];

    // 1. Consume Macro Includes
    while (!_isEof() && _peek().type == TokenType.At) {
      stmts.add(_parseInclude());
      _skipNewlines();
    }

    if (_isEof()) throw Exception("Syntax Error: Script is empty.");

    // 2. Parse exactly ONE TaskDef (FuncDef or Block)
    Expr mainTask;
    if (_peek().type == TokenType.LParen && _isFuncDefStart()) {
      mainTask = _parseFuncDef();
    } else if (_peek().type == TokenType.LBrace) {
      mainTask = _parseBlock();
    } else {
      throw Exception("Syntax Error: Expected main task definition (a closure or a block).");
    }
    stmts.add(mainTask);

    // 3. Assert EOF
    _skipNewlines();
    if (!_isEof()) {
      throw Exception("Syntax Error: Unexpected code outside of main task. A Hank script must contain exactly one Task definition.");
    }

    if (stmts.length == 1) return stmts[0];
    return BlockExpr(stmts, _getTd(stmts[0]));
  }

  Expr _parseStatement() {
    _skipNewlines();
    Token t = _peek();

    if (t.type == TokenType.Question) {
      return _parseFlowControl();
    }

    if (t.type == TokenType.At) {
      return _parseInclude();
    }

    Expr expr = _parseExpression();
    _skipNewlines();
    return expr;
  }

  Expr _parseFlowControl() {
    TokenData td = _consume(TokenType.Question);
    _consume(TokenType.LParen);
    Expr condition = _parseExpression();
    _consume(TokenType.RParen);
    Expr success = _parseBlock();

    Expr? fallback;
    Expr? rescue;
    String? catchVar;

    _skipNewlines();
    if (_peek().type == TokenType.Colon) {
      _consume(TokenType.Colon);
      fallback = _parseBlock();
    }

    _skipNewlines();
    if (_peek().type == TokenType.Rescue) {
      _consume(TokenType.Rescue);
      if (_peek().type == TokenType.LParen) {
        _consume(TokenType.LParen);
        catchVar = _consumeIdentifier();
        _consume(TokenType.RParen);
      }
      rescue = _parseBlock();
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
      throw Exception("Syntax Error: The '@' macro strictly requires a string literal path (e.g., @ \"utils\"). Identifier shorthand is not allowed.");
    }

    String? content = macroMap[rawPath];
    if (content == null) {
      throw _error('Macro resource not found: @$rawPath');
    }

    String taskName = rawPath.split('/').last.split('.').first;

    var lexer = Lexer(content);
    var subParser = Parser(lexer.tokenize(), rawPath, macroMap);
    Expr taskAst = subParser.parse();

    return AssignExpr(taskName, taskAst, td);
  }

  Expr _parseExpression() {
    return _parseAssignment();
  }

  Expr _parseAssignment() {
    Expr expr = _parsePrimary();

    if (_peek().type == TokenType.Assign) {
      if (expr is IdentExpr) {
        TokenData td = _consume(TokenType.Assign);
        Expr val = _parseExpression();
        return AssignExpr(expr.name, val, td);
      } else {
        throw _error('Invalid assignment target');
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
        expr = _parseArrayLiteral();
        break;
      case TokenType.LBrace:
        if (_isObjectLiteral()) {
          expr = _parseObjectLiteral();
        } else {
          expr = _parseBlock();
        }
        break;
      case TokenType.Caret:
        _consume(TokenType.Caret);
        Expr val;
        if (!_isEof() && ![TokenType.Newline, TokenType.RBrace, TokenType.RBracket, TokenType.Comma, TokenType.RParen].contains(_peek().type)) {
           val = _parseExpression();
        } else {
           val = LiteralExpr(Value.voidVal(), td);
        }
        expr = UnOpExpr('^', val, td);
        break;
      case TokenType.Not:
        _consume(TokenType.Not);
        expr = UnOpExpr('!', _parsePrimary(), td);
        break;
      default:
        throw _error('Unexpected token: ${t.type} (${t.literal})');
    }

    return _finishPrimary(expr);
  }

  Expr _finishPrimary(Expr expr) {
    while (true) {
      Token t = _peek();
      if (t.type == TokenType.LParen) {
        expr = FuncCallExpr(expr, _parseArgList(), t.td);
      } else if (t.type == TokenType.Dot) {
        _consume(TokenType.Dot);
        String name = _consumeIdentifier();
        expr = FieldExpr(expr, name, t.td);
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

  bool _isObjectLiteral() {
    int p = pos + 1;
    while (p < tokens.length && tokens[p].type == TokenType.Newline) p++;
    if (p >= tokens.length) return false;
    if (tokens[p].type == TokenType.RBrace) return true;
    if (tokens[p].type == TokenType.Identifier) {
       int next = p + 1;
       while (next < tokens.length && tokens[next].type == TokenType.Newline) next++;
       return next < tokens.length && tokens[next].type == TokenType.Colon;
    }
    return false;
  }

  Expr _parseObjectLiteral() {
    TokenData td = _consume(TokenType.LBrace);
    Map<String, Expr> fields = {};
    while (_peek().type != TokenType.RBrace && !_isEof()) {
      _skipNewlines();
      if (_peek().type == TokenType.RBrace) break;
      String key = _consumeIdentifier();
      _consume(TokenType.Colon);
      Expr val = _parseExpression();
      fields[key] = val;
      if (_peek().type == TokenType.Comma) _consume(TokenType.Comma);
    }
    _consume(TokenType.RBrace);
    return ObjectExpr(fields, td);
  }

  Expr _parseArrayLiteral() {
    TokenData td = _consume(TokenType.LBracket);
    List<Expr> items = [];
    while (_peek().type != TokenType.RBracket && !_isEof()) {
      _skipNewlines();
      if (_peek().type == TokenType.RBracket) break;
      items.add(_parseExpression());
      if (_peek().type == TokenType.Comma) _consume(TokenType.Comma);
    }
    _consume(TokenType.RBracket);
    return ArrayExpr(items, td);
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
    throw _error('Expected identifier, found ${t.type}');
  }

  TokenData _consume(TokenType type) {
    Token t = _peek();
    if (t.type == type) {
      pos++;
      return t.td;
    }
    throw _error('Expected $type, found ${t.literal}');
  }

  Token _peek() => tokens[pos];

  void _skipNewlines() {
    while (pos < tokens.length && tokens[pos].type == TokenType.Newline) {
      pos++;
    }
  }

  bool _isEof() => pos >= tokens.length || tokens[pos].type == TokenType.EOF;

  Exception _error(String msg) {
    TokenData td = _peek().td;
    return Exception('ERROR: $msg in $filename at\n\t${td.line}:\t${td.lineText}');
  }
}
