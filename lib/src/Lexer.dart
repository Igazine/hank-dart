import 'Types.dart';

class Lexer {
  final String source;
  int pos = 0;
  int line = 1;
  String lineText = '';

  Lexer(this.source) {
    _updateLineText();
  }

  void _updateLineText() {
    int start = 0;
    if (pos > 0) {
      int prevNewline = source.lastIndexOf('\n', pos - 1);
      if (prevNewline != -1) {
        start = prevNewline + 1;
      }
    }
    int end = source.indexOf('\n', pos);
    if (end == -1) end = source.length;
    lineText = source.substring(start, end);
  }

  List<Token> tokenize() {
    List<Token> tokens = [];
    while (pos < source.length) {
      String c = source[pos];
      
      if (_isWhitespace(c)) {
        if (c == '\n') {
          tokens.add(Token(TokenType.Newline, '\n', _td()));
          line++;
          pos++;
          _updateLineText();
        } else {
          pos++;
        }
        continue;
      }

      if (c == '/') {
        if (pos + 1 < source.length && source[pos + 1] == '/') {
          // Line comment
          while (pos < source.length && source[pos] != '\n') {
            pos++;
          }
          continue;
        } else if (_isRegexStart()) {
          tokens.add(_readRegex());
          continue;
        }
      }

      if (_isDigit(c)) {
        tokens.add(_readNumber());
        continue;
      }

      if (_isAlpha(c) || c == '_') {
        tokens.add(_readIdentifier());
        continue;
      }

      if (c == '"' || c == "'") {
        tokens.add(_readString(c));
        continue;
      }

      switch (c) {
        case '=': tokens.add(Token(TokenType.Assign, '=', _td())); break;
        case '?': tokens.add(Token(TokenType.Question, '?', _td())); break;
        case ':': tokens.add(Token(TokenType.Colon, ':', _td())); break;
        case '~': tokens.add(Token(TokenType.Rescue, '~', _td())); break;
        case '@': tokens.add(Token(TokenType.At, '@', _td())); break;
        case '#': tokens.add(Token(TokenType.Hash, '#', _td())); break;
        case '!': tokens.add(Token(TokenType.Not, '!', _td())); break;
        case '^': tokens.add(Token(TokenType.Caret, '^', _td())); break;
        case '.': tokens.add(Token(TokenType.Dot, '.', _td())); break;
        case ',': tokens.add(Token(TokenType.Comma, ',', _td())); break;
        case '(': tokens.add(Token(TokenType.LParen, '(', _td())); break;
        case ')': tokens.add(Token(TokenType.RParen, ')', _td())); break;
        case '{': tokens.add(Token(TokenType.LBrace, '{', _td())); break;
        case '}': tokens.add(Token(TokenType.RBrace, '}', _td())); break;
        case '[': tokens.add(Token(TokenType.LBracket, '[', _td())); break;
        case ']': tokens.add(Token(TokenType.RBracket, ']', _td())); break;
        default:
          // Unknown char, skip
      }
      pos++;
    }
    tokens.add(Token(TokenType.EOF, '', _td()));
    return tokens;
  }

  bool _isRegexStart() {
    int nextSlash = source.indexOf('/', pos + 1);
    if (nextSlash == -1) return false;
    String sub = source.substring(pos, nextSlash);
    return !sub.contains('\n');
  }

  Token _readRegex() {
    int start = pos;
    pos++;
    while (pos < source.length) {
      if (source[pos] == '/' && source[pos - 1] != '\\') {
        pos++;
        // Read flags
        while (pos < source.length && _isAlpha(source[pos])) {
          pos++;
        }
        return Token(TokenType.Regex, source.substring(start, pos), _td());
      }
      pos++;
    }
    return Token(TokenType.Regex, source.substring(start, pos), _td());
  }

  Token _readNumber() {
    int start = pos;
    bool hasDot = false;
    while (pos < source.length) {
      String c = source[pos];
      if (_isDigit(c)) {
        pos++;
      } else if (c == '.' && !hasDot && pos + 1 < source.length && _isDigit(source[pos + 1])) {
        hasDot = true;
        pos++;
      } else {
        break;
      }
    }
    return Token(TokenType.Number, source.substring(start, pos), _td());
  }

  Token _readIdentifier() {
    int start = pos;
    while (pos < source.length && (_isAlphaNumeric(source[pos]) || source[pos] == '_')) {
      pos++;
    }
    return Token(TokenType.Identifier, source.substring(start, pos), _td());
  }

  Token _readString(String quote) {
    int start = pos;
    pos++;
    while (pos < source.length) {
      if (source[pos] == quote && source[pos - 1] != '\\') {
        pos++;
        break;
      }
      pos++;
    }
    return Token(TokenType.String, source.substring(start, pos), _td());
  }

  TokenData _td() => TokenData(line: line, lineText: lineText);

  bool _isWhitespace(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';
  bool _isDigit(String c) => RegExp(r'[0-9]').hasMatch(c);
  bool _isAlpha(String c) => RegExp(r'[a-zA-Z]').hasMatch(c);
  bool _isAlphaNumeric(String c) => RegExp(r'[a-zA-Z0-9]').hasMatch(c);
}
