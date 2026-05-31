import 'dart:collection';
import 'Types.dart';
import 'ErrorRegistry.dart';

enum EvalResultType {
  Value,
  Return,
  Break,
  Error
}

class EvalResult {
  final EvalResultType type;
  final Value value;

  EvalResult({required this.type, required this.value});
}

class Interpreter implements ExecutionContext {
  final Scope? parentScope;
  late Scope globalScope;
  final Scope coreScope;
  final Map<int, String> localization;
  final int maxInstructions;
  int instructionCount = 0;
  int _depth = 0;

  Interpreter(this.parentScope, this.coreScope, {this.localization = const {}, this.maxInstructions = 0}) {
    globalScope = HankScope(parent: parentScope ?? coreScope);
  }

  Value run(Expr ast) {
    EvalResult res = _evalInScope(ast, globalScope);
    switch (res.type) {
      case EvalResultType.Value:
      case EvalResultType.Return:
        return res.value;
      case EvalResultType.Break:
        return Value.voidVal();
      case EvalResultType.Error:
        return res.value;
    }
  }

  @override
  Value eval(Expr node) {
    EvalResult res = _evalInScope(node, globalScope);
    switch (res.type) {
      case EvalResultType.Value:
      case EvalResultType.Return:
        return res.value;
      case EvalResultType.Break:
        return Value(type: ValueType.Opaque, label: '__ControlFlow', value: 'Break');
      case EvalResultType.Error:
        return res.value;
    }
  }

  @override
  bool isError(Value val) => val.type == ValueType.Error;

  @override
  Map<int, String> getLocalization() => localization;

  EvalResult _evalInScope(Expr node, Scope scope) {
    if (maxInstructions > 0) {
      instructionCount++;
      if (instructionCount > maxInstructions) {
        return EvalResult(type: EvalResultType.Error, value: Value(type: ValueType.Error, code: 4008, args: [Value.number(maxInstructions.toDouble())]));
      }
    }

    const int maxDepth = 500;
    if (_depth > maxDepth) {
      return EvalResult(type: EvalResultType.Error, value: Value(type: ValueType.Error, code: 4006, args: [Value.string("Stack overflow")]));
    }

    if (node is LiteralExpr) return EvalResult(type: EvalResultType.Value, value: node.value);

    if (node is ErrorExpr) {
      List<Value> args = [];
      for (var argExpr in node.args) {
        var res = _evalInScope(argExpr, scope);
        if (res.type != EvalResultType.Value) return res;
        args.add(res.value);
      }
      return EvalResult(type: EvalResultType.Value, value: Value(type: ValueType.Error, code: node.code, args: args));
    }

    if (node is IdentExpr) {
      if (node.isCore) return EvalResult(type: EvalResultType.Value, value: coreScope.get(node.name));
      Value val = scope.get(node.name);
      if (val.type == ValueType.Void) {
        return EvalResult(type: EvalResultType.Value, value: coreScope.get(node.name));
      }
      return EvalResult(type: EvalResultType.Value, value: val);
    }

    if (node is AssignExpr) {
      EvalResult res = _evalInScope(node.value, scope);
      if (res.type == EvalResultType.Value) {
        scope.set(node.name, res.value);
      }
      return res;
    }

    if (node is BlockExpr) {
      // --- TASK HOISTING PASS ---
      for (var stmt in node.stmts) {
        if (stmt is AssignExpr) {
           if (stmt.value is FuncDefExpr) {
             var res = _evalInScope(stmt.value, scope);
             if (res.type == EvalResultType.Value) scope.set(stmt.name, res.value);
           } else if (stmt.value is AssignExpr) {
             var inner = stmt.value as AssignExpr;
             if (inner.value is FuncDefExpr) {
               var res = _evalInScope(inner.value, scope);
               if (res.type == EvalResultType.Value) scope.set(inner.name, res.value);
             }
           }
        }
      }

      Value last = Value.voidVal();
      for (var stmt in node.stmts) {
        if (stmt is AssignExpr) {
           if (stmt.value is FuncDefExpr) continue;
           if (stmt.value is AssignExpr) {
             var inner = stmt.value as AssignExpr;
             if (inner.value is FuncDefExpr) continue;
           }
        }
        EvalResult res = _evalInScope(stmt, scope);
        if (res.type != EvalResultType.Value) return res;
        last = res.value;
      }
      return EvalResult(type: EvalResultType.Value, value: last);
    }

    if (node is FuncDefExpr) {
      return EvalResult(
        type: EvalResultType.Value,
        value: Value(
          type: ValueType.Task,
          task: TaskValue(
            isNative: false,
            name: 'anonymous',
            params: node.params,
            body: node.body,
            closure: scope,
          ),
        ),
      );
    }

    if (node is FuncCallExpr) {
      EvalResult tRes = _evalInScope(node.target, scope);
      if (tRes.type != EvalResultType.Value) return tRes;
      Value target = tRes.value;

      List<Value> args = [];
      for (var argExpr in node.args) {
        var aRes = _evalInScope(argExpr, scope);
        if (aRes.type != EvalResultType.Value) return aRes;
        args.add(aRes.value);
      }
      return _callInternal(target, args, scope);
    }

    if (node is MapExpr) {
      Map<String, Value> fields = {};
      for (var entry in node.fields.entries) {
        var res = _evalInScope(entry.value, scope);
        if (res.type != EvalResultType.Value) return res;
        fields[entry.key] = res.value;
      }
      return EvalResult(type: EvalResultType.Value, value: Value(type: ValueType.Map, value: fields));
    }

    if (node is ArrayExpr) {
      List<Value> items = [];
      for (var itemExpr in node.items) {
        var res = _evalInScope(itemExpr, scope);
        if (res.type != EvalResultType.Value) return res;
        items.add(res.value);
      }
      return EvalResult(type: EvalResultType.Value, value: Value(type: ValueType.Array, value: items));
    }

    if (node is UnOpExpr) {
      EvalResult res = _evalInScope(node.right, scope);
      if (res.type != EvalResultType.Value) return res;
      Value val = res.value;

      if (node.op == '^') {
        return EvalResult(type: EvalResultType.Return, value: val);
      }
      if (node.op == '!') {
        return EvalResult(type: EvalResultType.Value, value: (val.type == ValueType.Void) ? Value.number(1.0) : Value.voidVal());
      }
    }

    if (node is FlowControlExpr) {
      EvalResult cRes = _evalInScope(node.condition, scope);
      EvalResult branchRes;

      if (cRes.type == EvalResultType.Value) {
        if (cRes.value.type != ValueType.Void) {
          branchRes = _evalInScope(node.success, scope);
        } else if (node.fallback != null) {
          branchRes = _evalInScope(node.fallback!, scope);
        } else {
          branchRes = EvalResult(type: EvalResultType.Value, value: Value.voidVal());
        }
      } else {
        branchRes = cRes;
      }

      if (branchRes.type == EvalResultType.Error && node.rescue != null) {
        Scope rescueScope = HankScope(parent: scope);
        if (node.catchVar != null) {
           rescueScope.set(node.catchVar!, branchRes.value);
        }
        return _evalInScope(node.rescue!, rescueScope);
      }
      return branchRes;
    }

    return EvalResult(type: EvalResultType.Value, value: Value.voidVal());
  }

  @override
  Value call(Value task, List<Value> args) {
    List<Value> finalArgs = args;
    if (task.type == ValueType.Task && task.task != null && !task.task!.isNative) {
      if (args.length > task.task!.params!.length) {
        finalArgs = args.sublist(0, task.task!.params!.length);
      }
    }
    EvalResult res = _callInternal(task, finalArgs, globalScope);
    switch (res.type) {
      case EvalResultType.Value:
      case EvalResultType.Return:
        return res.value;
      case EvalResultType.Break:
        return Value(type: ValueType.Opaque, label: '__ControlFlow', value: 'Break');
      case EvalResultType.Error:
        return res.value;
    }
  }

  EvalResult _callInternal(Value task, List<Value> args, Scope scope) {
    if (task.type != ValueType.Task) {
      return EvalResult(type: EvalResultType.Error, value: Value(type: ValueType.Error, code: 4001, args: [Value.string(task.toString())]));
    }
    TaskValue t = task.task!;

    if (t.isNative) {
      try {
        Value res = t.native!(args, this);
        if (res.type == ValueType.Opaque && res.label == '__ControlFlow' && res.value == 'Break') {
          return EvalResult(type: EvalResultType.Break, value: Value.voidVal());
        }
        if (res.type == ValueType.Error) return EvalResult(type: EvalResultType.Error, value: res);
        return EvalResult(type: EvalResultType.Value, value: res);
      } catch (e) {
        return EvalResult(type: EvalResultType.Error, value: Value(type: ValueType.Error, code: 4006, args: [Value.string(e.toString())]));
      }
    } else {
      List<Value> finalArgs = args;
      if (args.length > t.params!.length) {
        finalArgs = args.sublist(0, t.params!.length);
      }

      _depth++;
      Scope callScope = HankScope(parent: t.closure);
      
      List<Param> params = t.params!;
      for (int i = 0; i < params.length; i++) {
        Param p = params[i];
        Value val = Value.voidVal();
        if (i < finalArgs.length) {
          val = finalArgs[i];
        } else if (p.defaultValue != null) {
          var pRes = _evalInScope(p.defaultValue!, callScope);
          if (pRes.type != EvalResultType.Value) return pRes;
          val = pRes.value;
        } else if (!p.isOptional) {
          return EvalResult(type: EvalResultType.Error, value: Value(type: ValueType.Error, code: 4003, args: [Value.string(p.name)]));
        }
        callScope.set(p.name, val);
      }

      EvalResult res = _evalInScope(t.body!, callScope);
      _depth--;
      if (res.type == EvalResultType.Value || res.type == EvalResultType.Return) {
        if (res.value.type == ValueType.Error) return EvalResult(type: EvalResultType.Error, value: res.value);
        return EvalResult(type: EvalResultType.Value, value: res.value);
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
