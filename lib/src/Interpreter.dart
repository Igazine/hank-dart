import 'dart:collection';
import 'Types.dart';

class Interpreter implements ExecutionContext {
  final Scope? parentScope;
  late Scope globalScope;
  final Scope coreScope;

  Interpreter(this.parentScope, this.coreScope) {
    globalScope = HankScope(parent: parentScope ?? coreScope);
  }

  Interpreter.withCore(this.coreScope) : parentScope = null {
    globalScope = HankScope(parent: coreScope);
  }

  Value run(Expr ast) {
    return eval(ast);
  }

  @override
  Value eval(Expr node) {
    return _evalInScope(node, globalScope);
  }

  Value _evalInScope(Expr node, Scope scope) {
    if (node is LiteralExpr) return node.value;

    if (node is IdentExpr) {
      if (node.isCore) return coreScope.get(node.name);
      return scope.get(node.name);
    }

    if (node is AssignExpr) {
      Value val = _evalInScope(node.value, scope);
      scope.set(node.name, val);
      return val;
    }

    if (node is BlockExpr) {
      // --- TASK HOISTING PASS ---
      for (var stmt in node.stmts) {
        if (stmt is AssignExpr) {
           if (stmt.value is FuncDefExpr) {
             scope.set(stmt.name, _evalInScope(stmt.value, scope));
           } else if (stmt.value is AssignExpr) {
             // Handle nested macro assignments for hoisting
             var inner = stmt.value as AssignExpr;
             if (inner.value is FuncDefExpr) {
               scope.set(inner.name, _evalInScope(inner.value, scope));
             }
           }
        }
      }

      Value last = Value.voidVal();
      for (var stmt in node.stmts) {
        last = _evalInScope(stmt, scope);
        if (last.type == ValueType.Void && last.value == '_RETURN_') return last;
      }
      return last;
    }

    if (node is FuncDefExpr) {
      return Value(
        type: ValueType.Task,
        task: TaskValue(
          isNative: false,
          name: 'anonymous',
          params: node.params,
          body: node.body,
          closure: scope,
        ),
      );
    }

    if (node is FuncCallExpr) {
      Value target = _evalInScope(node.target, scope);
      List<Value> args = node.args.map((a) => _evalInScope(a, scope)).toList();
      return _callInternal(target, args);
    }

    if (node is FieldExpr) {
      Value target = _evalInScope(node.target, scope);
      if (target.type == ValueType.Object) {
        Map<String, Value> map = target.value;
        return map[node.name] ?? Value.voidVal();
      }
      return Value.voidVal();
    }

    if (node is ObjectExpr) {
      Map<String, Value> fields = {};
      node.fields.forEach((k, v) {
        fields[k] = _evalInScope(v, scope);
      });
      return Value(type: ValueType.Object, value: fields);
    }

    if (node is ArrayExpr) {
      List<Value> items = node.items.map((i) => _evalInScope(i, scope)).toList();
      return Value(type: ValueType.Array, value: items);
    }

    if (node is UnOpExpr) {
      if (node.op == '^') {
        Value val = _evalInScope(node.right, scope);
        return Value(type: ValueType.Void, value: '_RETURN_', task: TaskValue(isNative: true, name: 'return', native: (a, c) => val));
      }
      if (node.op == '!') {
        Value val = _evalInScope(node.right, scope);
        return (val.type == ValueType.Void) ? Value.number(1.0) : Value.voidVal();
      }
    }

    if (node is FlowControlExpr) {
      Value cond = _evalInScope(node.condition, scope);
      bool isTruthy = cond.type != ValueType.Void;

      if (isTruthy) {
        try {
          return _evalInScope(node.success, scope);
        } catch (e) {
          if (node.rescue != null) {
            Scope rescueScope = HankScope(parent: scope);
            if (node.catchVar != null) {
               rescueScope.set(node.catchVar!, Value.string(e.toString()));
            }
            return _evalInScope(node.rescue!, rescueScope);
          }
          rethrow;
        }
      } else {
        if (node.fallback != null) return _evalInScope(node.fallback!, scope);
      }
      return Value.voidVal();
    }

    return Value.voidVal();
  }

  @override
  Value call(Value task, List<Value> args) {
    List<Value> finalArgs = args;
    if (task.type == ValueType.Task && task.task != null && !task.task!.isNative) {
      if (args.length > task.task!.params!.length) {
        finalArgs = args.sublist(0, task.task!.params!.length);
      }
    }
    return _callInternal(task, finalArgs);
  }

  Value _callInternal(Value task, List<Value> args) {
    if (task.type != ValueType.Task) throw Exception('Target is not a function: ${task.toString()}');
    TaskValue t = task.task!;

    if (t.isNative) {
      return t.native!(args, this);
    } else {
      // Arity Enforcement
      if (args.length > t.params!.length) {
        throw Exception('Too many arguments');
      }

      Scope callScope = HankScope(parent: t.closure);
      
      List<Param> params = t.params!;
      for (int i = 0; i < params.length; i++) {
        Param p = params[i];
        Value val = Value.voidVal();
        if (i < args.length) {
          val = args[i];
        } else if (p.defaultValue != null) {
          val = _evalInScope(p.defaultValue!, callScope);
        } else if (!p.isOptional) {
          throw Exception('Missing required parameter: ${p.name}');
        }
        callScope.set(p.name, val);
      }

      Value res = _evalInScope(t.body!, callScope);
      if (res.type == ValueType.Void && res.value == '_RETURN_') {
        return res.task!.native!([], this);
      }
      return res;
    }
  }

  @override
  Scope get scope => globalScope;
}

class HankScope implements Scope {
  final Map<String, Value> values = {};
  final Scope? parent;

  HankScope({this.parent});

  @override
  Value get(String name) {
    if (values.containsKey(name)) return values[name]!;
    if (parent != null) return parent!.get(name);
    return Value.voidVal();
  }

  @override
  void set(String name, Value val) {
    values[name] = val;
  }

  @override
  bool exists(String name) {
    return values.containsKey(name) || (parent?.exists(name) ?? false);
  }

  @override
  String toString() => 'Scope($values)';
}
