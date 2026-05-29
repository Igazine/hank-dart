import 'dart:collection';

enum ValueType {
  Void,
  Number,
  String,
  Array,
  Object,
  Opaque,
  Task
}

class Value {
  final ValueType type;
  final dynamic value;
  final String? label;   // For Opaque
  final TaskValue? task;  // For Task

  Value({
    required this.type,
    this.value,
    this.label,
    this.task,
  });

  @override
  String toString() {
    switch (type) {
      case ValueType.String: return (value ?? 'null') as String;
      case ValueType.Number: 
        String s = (value ?? 0.0).toString();
        if (s.endsWith('.0')) return s.substring(0, s.length - 2);
        return s;
      case ValueType.Void: return 'Void';
      case ValueType.Array: return '[Array]';
      case ValueType.Object: return '{Object}';
      case ValueType.Opaque: return '[Opaque:${label ?? 'Unknown'}]';
      case ValueType.Task: return '[Task]';
    }
  }

  static Value voidVal() => Value(type: ValueType.Void);
  static Value number(double n) => Value(type: ValueType.Number, value: n);
  static Value string(String s) => Value(type: ValueType.String, value: s);
}

class TaskValue {
  final bool isNative;
  final String name;
  final List<Param>? params;
  final Expr? body;
  final Scope? closure;
  final NativeFunc? native;

  TaskValue({
    required this.isNative,
    required this.name,
    this.params,
    this.body,
    this.closure,
    this.native,
  });
}

class Param {
  final String name;
  final bool isOptional;
  final Expr? defaultValue;

  Param({
    required this.name,
    required this.isOptional,
    this.defaultValue,
  });
}

typedef NativeFunc = Value Function(List<Value> args, ExecutionContext ctx);

abstract class ExecutionContext {
  Value call(Value task, List<Value> args);
  Value eval(Expr node);
  Scope get scope;
}

abstract class Scope {
  Value get(String name);
  void set(String name, Value val);
  bool exists(String name);
}

/**
 * A base class for all Hank resources.
 * Encapsulates the unique identity, raw content, and parsed AST of a script.
 */
abstract class Resource {
  String? content;
  final String id;
  Expr? ast;

  Resource(this.id);

  /**
   * Fulfills the raw content of the resource from its source.
   */
  Future<void> load();

  /**
   * Resolves a relative identifier into a new Resource instance.
   * @param id The string identifier (e.g., from a @ macro).
   */
  Resource resolve(String id);
}

class TokenData {
  final int line;
  final String lineText;

  TokenData({required this.line, required this.lineText});

  factory TokenData.empty() => TokenData(line: 0, lineText: '');
}

enum TokenType {
  Identifier, // 0
  Number,     // 1
  String,     // 2
  Assign,     // = 3
  Question,   // ? 4
  Colon,      // : 5
  Rescue,     // ~ 6
  At,         // @ 7
  Hash,       // # 8
  Not,        // ! 9
  Caret,      // ^ 10
  Dot,        // . 11
  Comma,      // , 12
  LParen,     // ( 13
  RParen,     // ) 14
  LBrace,     // { 15
  RBrace,     // } 16
  LBracket,   // [ 17
  RBracket,   // ] 19
  Newline,    // 20
  EOF,        // 21
  Error       // 22
}

class Token {
  final TokenType type;
  final String literal;
  final TokenData td;

  Token(this.type, this.literal, this.td);
}

abstract class Expr {
  final TokenData td;
  Expr(this.td);
}

class BlockExpr extends Expr {
  final List<Expr> stmts;
  BlockExpr(this.stmts, TokenData td) : super(td);
}

class AssignExpr extends Expr {
  final String name;
  final Expr value;
  AssignExpr(this.name, this.value, TokenData td) : super(td);
}

class LiteralExpr extends Expr {
  final Value value;
  LiteralExpr(this.value, TokenData td) : super(td);
}

class IdentExpr extends Expr {
  final String name;
  final bool isCore;
  IdentExpr(this.name, this.isCore, TokenData td) : super(td);
}

class FieldExpr extends Expr {
  final Expr target;
  final String name;
  FieldExpr(this.target, this.name, TokenData td) : super(td);
}

class FuncDefExpr extends Expr {
  final List<Param> params;
  final Expr body;
  FuncDefExpr(this.params, this.body, TokenData td) : super(td);
}

class FuncCallExpr extends Expr {
  final Expr target;
  final List<Expr> args;
  FuncCallExpr(this.target, this.args, TokenData td) : super(td);
}

class UnOpExpr extends Expr {
  final String op;
  final Expr right;
  UnOpExpr(this.op, this.right, TokenData td) : super(td);
}

class ObjectExpr extends Expr {
  final Map<String, Expr> fields;
  ObjectExpr(this.fields, TokenData td) : super(td);
}

class ArrayExpr extends Expr {
  final List<Expr> items;
  ArrayExpr(this.items, TokenData td) : super(td);
}

class FlowControlExpr extends Expr {
  final Expr condition;
  final Expr success;
  final Expr? fallback;
  final Expr? rescue;
  final String? catchVar;
  FlowControlExpr({
    required this.condition,
    required this.success,
    this.fallback,
    this.rescue,
    this.catchVar,
    required TokenData td,
  }) : super(td);
}

abstract class IHankSerializable {
  String serializeHank();
}

abstract class HankExtension {
  String get name;
  Map<String, Map<String, NativeFunc>> getModules();
}

enum HankError {
  // Lexical Errors (10xx)
  UnexpectedCharacter, // 1001
  UnclosedStringLiteral, // 1002

  // Syntax Errors (20xx)
  EmptyScript, // 2001
  ExpectedMainTask, // 2002
  UnexpectedCodeOutsideMainTask, // 2003
  InvalidAssignmentTarget, // 2004
  UnexpectedToken, // 2005
  MacroRequiresString, // 2006
  ExpectedIdentifier, // 2007

  // Resolution & Runner Errors (30xx)
  CircularDependency, // 3001
  ResourceContentNotLoaded, // 3002
  ScriptMustBeTask, // 3003
  MacroResourceNotFound, // 3004

  // Runtime Errors (40xx)
  TargetNotFunction, // 4001
  TooManyArguments, // 4002
  MissingRequiredParameter, // 4003
  Halt, // 4004
  BitwiseOutOfBounds, // 4005
  GenericRuntimeError, // 4006
}

class HankErrorValue implements Exception {
  final HankError code;
  final String message;

  HankErrorValue(this.code, this.message);

  @override
  String toString() => message;
}
