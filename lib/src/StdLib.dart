import 'dart:convert';
import 'Types.dart';
import 'ErrorRegistry.dart';

class StdLib implements HankExtension {
  @override
  String get name => "StdLib";

  final Map<String, Value> envState = {};

  /**
   * Returns the recommended standard library modules.
   * Developers should register these manually on their Runner.
   */
  @override
  Map<String, NativeFunc> getTasks() {
    String valToString(Value v) {
      return v.toString();
    }

    String typeToString(ValueType t) {
      switch (t) {
        case ValueType.Void: return "Void";
        case ValueType.Number: return "Number";
        case ValueType.String: return "String";
        case ValueType.Array: return "Array";
        case ValueType.Map: return "Map";
        case ValueType.Opaque: return "Opaque";
        case ValueType.Task: return "Task";
        case ValueType.Error: return "Error";
      }
    }

    Value mapAnyToHank(dynamic v) {
      if (v == null) return Value.voidVal();
      if (v is IHankSerializable) return Value.string(v.serializeHank());
      if (v is double) return Value.number(v);
      if (v is int) return Value.number(v.toDouble());
      if (v is String) return Value.string(v);
      if (v is bool) return v ? Value.number(1.0) : Value.voidVal();
      if (v is List) return Value(type: ValueType.Array, value: v.map(mapAnyToHank).toList());
      if (v is Map) {
        Map<String, Value> map = {};
        v.forEach((k, val) {
          map[k.toString()] = mapAnyToHank(val);
        });
        return Value(type: ValueType.Map, value: map);
      }
      return Value.voidVal();
    }

    bool hasOpaque(Value v) {
      if (v.type == ValueType.Opaque) return true;
      if (v.type == ValueType.Array) {
        return (v.value as List<Value>).any(hasOpaque);
      }
      if (v.type == ValueType.Map) {
        return (v.value as Map<String, Value>).values.any(hasOpaque);
      }
      return false;
    }

    dynamic mapHankToAny(Value v) {
      switch (v.type) {
        case ValueType.Number: return v.value as double;
        case ValueType.String: return v.value as String;
        case ValueType.Array: return (v.value as List<Value>).map(mapHankToAny).toList();
        case ValueType.Map:
          Map<String, dynamic> obj = {};
          (v.value as Map<String, Value>).forEach((k, val) {
            obj[k] = mapHankToAny(val);
          });
          return obj;
        default: return null;
      }
    }

    bool hankEquals(Value a, Value b) {
      if (a.type != b.type) return false;
      switch (a.type) {
        case ValueType.Void: return true;
        case ValueType.Number: return a.value == b.value;
        case ValueType.String: return a.value == b.value;
        case ValueType.Array:
          List<Value> l1 = a.value;
          List<Value> l2 = b.value;
          if (l1.length != l2.length) return false;
          for (int i = 0; i < l1.length; i++) {
            if (!hankEquals(l1[i], l2[i])) return false;
          }
          return true;
        case ValueType.Map:
          Map<String, Value> m1 = a.value;
          Map<String, Value> m2 = b.value;
          if (m1.length != m2.length) return false;
          for (var key in m1.keys) {
            if (!m2.containsKey(key) || !hankEquals(m1[key]!, m2[key]!)) return false;
          }
          return true;
        case ValueType.Opaque:
          return a.label == b.label && a.value == b.value;
        case ValueType.Error:
          if (a.code != b.code || a.args?.length != b.args?.length) return false;
          for (int i = 0; i < (a.args?.length ?? 0); i++) {
            if (!hankEquals(a.args![i], b.args![i])) return false;
          }
          return true;
        default: return false;
      }
    }

    return {
      'log_print': (args, ctx) { print(args.map(valToString).join(' ')); return Value.voidVal(); },
      'log_error': (args, ctx) { print('[ERROR] ' + args.map(valToString).join(' ')); return Value.voidVal(); },
      'log_warn': (args, ctx) { print('[WARN] ' + args.map(valToString).join(' ')); return Value.voidVal(); },
      
      'runtime_halt': (args, ctx) {
        int code = 0;
        if (args.length > 0 && args[0].type == ValueType.Number) code = (args[0].value as double).toInt();
        throw Exception('HANK_HALT:$code');
      },
      'runtime_elapsedTime': (args, ctx) => Value.number(0.0),
      'runtime_signal': (args, ctx) {
        if (args.isNotEmpty) print('[SIGNAL] ${valToString(args[0])}');
        return Value.voidVal();
      },

      'loop_while': (args, ctx) {
        if (args.length < 2) return Value.voidVal();
        Value cond = args[0];
        Value body = args[1];
        Value last = Value.voidVal();
        while (true) {
          Value condVal = ctx.call(cond, []);
          if (ctx.isError(condVal)) return condVal;
          if (condVal.type == ValueType.Void) break;
          
          Value res = ctx.call(body, []);
          if (res.type == ValueType.Opaque && res.label == '__ControlFlow' && res.value == 'Break') break;
          if (ctx.isError(res)) return res;
          last = res;
        }
        return last;
      },
      'loop_break': (args, ctx) => Value(type: ValueType.Opaque, label: '__ControlFlow', value: 'Break'),

      'env_get': (args, ctx) {
        if (args.isEmpty) return Value.voidVal();
        return envState[valToString(args[0])] ?? Value.voidVal();
      },
      'env_set': (args, ctx) {
        if (args.length < 2) return Value.voidVal();
        envState[valToString(args[0])] = args[1];
        return Value.voidVal();
      },
      'env_keys': (args, ctx) => Value(type: ValueType.Array, value: envState.keys.map((k) => Value.string(k)).toList()),

      'str_length': (args, ctx) {
        if (args.isEmpty) return Value.voidVal();
        if (args[0].type != ValueType.String) {
          return Value(type: ValueType.Error, code: 4007, args: [Value.string("String"), Value.string(typeToString(args[0].type)), Value.string("str_length")]);
        }
        return Value.number(valToString(args[0]).length.toDouble());
      },
      'str_format': (args, ctx) {
        if (args.isEmpty) return Value.voidVal();
        String res = valToString(args[0]);
        for (int i = 1; i < args.length; i++) {
          res = res.replaceAll('%$i', valToString(args[i]));
        }
        return Value.string(res);
      },
      'str_concat': (args, ctx) => Value.string(args.map(valToString).join('')),
      'str_trim': (args, ctx) {
        if (args.isEmpty) return Value.voidVal();
        if (args[0].type != ValueType.String) {
          return Value(type: ValueType.Error, code: 4007, args: [Value.string("String"), Value.string(typeToString(args[0].type)), Value.string("str_trim")]);
        }
        return Value.string(valToString(args[0]).trim());
      },

      'num_parse': (args, ctx) {
        if (args.isEmpty) return Value.voidVal();
        String s = valToString(args[0]);
        int base = 0;
        if (args.length > 1 && args[1].type == ValueType.Number) {
          base = (args[1].value as double).toInt();
        }
        
        try {
          if (base == 0) {
            if (s.startsWith("0x")) return Value.number(int.parse(s.substring(2), radix: 16).toDouble());
            if (s.startsWith("0b")) return Value.number(int.parse(s.substring(2), radix: 2).toDouble());
            if (s.startsWith("0o")) return Value.number(int.parse(s.substring(2), radix: 8).toDouble());
            return Value.number(double.parse(s));
          }
          return Value.number(int.parse(s, radix: base).toDouble());
        } catch (e) {
          return Value.voidVal();
        }
      },
      'num_format': (args, ctx) {
        if (args.isEmpty || args[0].type != ValueType.Number) return Value.voidVal();
        int n = (args[0].value as double).toInt();
        int base = 10;
        if (args.length > 1 && args[1].type == ValueType.Number) {
          base = (args[1].value as double).toInt();
        }
        if (base < 2 || base > 36) return Value.voidVal();
        return Value.string(n.toRadixString(base));
      },

      'math_add': (args, ctx) {
        double sum = 0.0;
        for (var a in args) {
          if (a.type != ValueType.Number) {
            return Value(type: ValueType.Error, code: 4007, args: [Value.string("Number"), Value.string(typeToString(a.type)), Value.string("math_add")]);
          }
          sum += a.value;
        }
        return Value.number(sum);
      },
      'math_sub': (args, ctx) {
        if (args.length < 2) return Value.voidVal();
        if (args[0].type != ValueType.Number || args[1].type != ValueType.Number) {
          Value faulty = args[0].type != ValueType.Number ? args[0] : args[1];
          return Value(type: ValueType.Error, code: 4007, args: [Value.string("Number"), Value.string(typeToString(faulty.type)), Value.string("math_sub")]);
        }
        return Value.number((args[0].value as double) - (args[1].value as double));
      },
      'math_mul': (args, ctx) {
        if (args.isEmpty) return Value.number(0.0);
        double res = 1.0;
        for (var a in args) {
          if (a.type != ValueType.Number) {
            return Value(type: ValueType.Error, code: 4007, args: [Value.string("Number"), Value.string(typeToString(a.type)), Value.string("math_mul")]);
          }
          res *= a.value;
        }
        return Value.number(res);
      },
      'math_div': (args, ctx) {
        if (args.length < 2) return Value.voidVal();
        if (args[0].type != ValueType.Number || args[1].type != ValueType.Number) {
          Value faulty = args[0].type != ValueType.Number ? args[0] : args[1];
          return Value(type: ValueType.Error, code: 4007, args: [Value.string("Number"), Value.string(typeToString(faulty.type)), Value.string("math_div")]);
        }
        if (args[1].value == 0) return Value.voidVal();
        return Value.number((args[0].value as double) / (args[1].value as double));
      },
      'math_gt': (args, ctx) {
        if (args.length < 2) return Value.voidVal();
        if (args[0].type != ValueType.Number || args[1].type != ValueType.Number) {
          Value faulty = args[0].type != ValueType.Number ? args[0] : args[1];
          return Value(type: ValueType.Error, code: 4007, args: [Value.string("Number"), Value.string(typeToString(faulty.type)), Value.string("math_gt")]);
        }
        return ((args[0].value as double) > (args[1].value as double) ? Value.number(1.0) : Value.voidVal());
      },
      'math_lt': (args, ctx) {
        if (args.length < 2) return Value.voidVal();
        if (args[0].type != ValueType.Number || args[1].type != ValueType.Number) {
          Value faulty = args[0].type != ValueType.Number ? args[0] : args[1];
          return Value(type: ValueType.Error, code: 4007, args: [Value.string("Number"), Value.string(typeToString(faulty.type)), Value.string("math_lt")]);
        }
        return ((args[0].value as double) < (args[1].value as double) ? Value.number(1.0) : Value.voidVal());
      },
      'math_eq': (args, ctx) => (args.length < 2) ? Value.voidVal() : (hankEquals(args[0], args[1]) ? Value.number(1.0) : Value.voidVal()),

      'logic_and': (args, ctx) {
        if (args.isEmpty) return Value.voidVal();
        Value last = Value.voidVal();
        for (var a in args) {
          if (a.type == ValueType.Void) return Value.voidVal();
          last = a;
        }
        return last;
      },
      'logic_or': (args, ctx) {
        for (var a in args) {
          if (a.type != ValueType.Void) return a;
        }
        return Value.voidVal();
      },
      'logic_eq': (args, ctx) => (args.length < 2) ? Value.voidVal() : (hankEquals(args[0], args[1]) ? Value.number(1.0) : Value.voidVal()),

      'arr_length': (args, ctx) {
        if (args.isEmpty) return Value.voidVal();
        if (args[0].type != ValueType.Array) {
          return Value(type: ValueType.Error, code: 4007, args: [Value.string("Array"), Value.string(typeToString(args[0].type)), Value.string("arr_length")]);
        }
        return Value.number((args[0].value as List).length.toDouble());
      },
      'arr_get': (args, ctx) {
         if (args.length < 2) return Value.voidVal();
         if (args[0].type != ValueType.Array) return Value(type: ValueType.Error, code: 4007, args: [Value.string("Array"), Value.string(typeToString(args[0].type)), Value.string("arr_get")]);
         if (args[1].type != ValueType.Number) return Value(type: ValueType.Error, code: 4007, args: [Value.string("Number"), Value.string(typeToString(args[1].type)), Value.string("arr_get")]);
         List<Value> l = args[0].value;
         int idx = (args[1].value as double).toInt();
         if (idx < 0 || idx >= l.length) return Value.voidVal();
         return l[idx];
      },
      'arr_push': (args, ctx) {
         if (args.length < 2) return Value.voidVal();
         if (args[0].type != ValueType.Array) return Value(type: ValueType.Error, code: 4007, args: [Value.string("Array"), Value.string(typeToString(args[0].type)), Value.string("arr_push")]);
         (args[0].value as List<Value>).add(args[1]);
         return Value.voidVal();
      },
      'arr_pop': (args, ctx) {
         if (args.isEmpty) return Value.voidVal();
         if (args[0].type != ValueType.Array) return Value(type: ValueType.Error, code: 4007, args: [Value.string("Array"), Value.string(typeToString(args[0].type)), Value.string("arr_pop")]);
         List<Value> l = args[0].value;
         if (l.isNotEmpty) return l.removeLast();
         return Value.voidVal();
      },
      'arr_each': (args, ctx) {
         if (args.length < 2) return Value.voidVal();
         if (args[0].type != ValueType.Array) return Value(type: ValueType.Error, code: 4007, args: [Value.string("Array"), Value.string(typeToString(args[0].type)), Value.string("arr_each")]);
         List<Value> items = List.from(args[0].value as List<Value>);
         for (int i = 0; i < items.length; i++) {
           Value res = ctx.call(args[1], [items[i], Value.number(i.toDouble())]);
           if (res.type == ValueType.Opaque && res.label == '__ControlFlow' && res.value == 'Break') break;
           if (ctx.isError(res)) return res;
         }
         return Value.voidVal();
      },

      'map_get': (args, ctx) {
        if (args.length < 2) return Value.voidVal();
        if (args[0].type != ValueType.Map) return Value.voidVal();
        return ((args[0].value as Map<String, Value>)[valToString(args[1])] ?? Value.voidVal());
      },
      'map_set': (args, ctx) {
        if (args.length < 3) return Value.voidVal();
        if (args[0].type != ValueType.Map) {
          return Value(type: ValueType.Error, code: 4007, args: [Value.string("Map"), Value.string(typeToString(args[0].type)), Value.string("map_set")]);
        }
        (args[0].value as Map<String, Value>)[valToString(args[1])] = args[2];
        return Value.voidVal();
      },
      'map_keys': (args, ctx) => (args.isNotEmpty && args[0].type == ValueType.Map) ? Value(type: ValueType.Array, value: (args[0].value as Map<String, Value>).keys.map((k) => Value.string(k)).toList()) : Value.voidVal(),

      'json_parse': (args, ctx) {
        if (args.isEmpty) return Value.voidVal();
        try {
          return mapAnyToHank(jsonDecode(valToString(args[0])));
        } catch (e) {
          return Value.voidVal();
        }
      },
      'json_stringify': (args, ctx) {
        if (args.isEmpty) return Value.voidVal();
        if (hasOpaque(args[0])) return Value.voidVal();
        try {
          return Value.string(jsonEncode(mapHankToAny(args[0])));
        } catch (e) {
          return Value.voidVal();
        }
      },

      'err_code': (args, ctx) {
         if (args.isEmpty) return Value.voidVal();
         if (args[0].type != ValueType.Error) return Value(type: ValueType.Error, code: 4007, args: [Value.string("Error"), Value.string(typeToString(args[0].type)), Value.string("err_code")]);
         return Value.number(args[0].code!.toDouble());
      },
      'err_message': (args, ctx) {
         if (args.isEmpty) return Value.voidVal();
         if (args[0].type != ValueType.Error) return Value(type: ValueType.Error, code: 4007, args: [Value.string("Error"), Value.string(typeToString(args[0].type)), Value.string("err_message")]);
         Value err = args[0];
         Map<int, String> loc = ctx.getLocalization();
         String tmpl = loc[err.code] ?? "Unknown Error";
         for (int i = 0; i < (err.args?.length ?? 0); i++) {
           tmpl = tmpl.replaceAll('{$i}', valToString(err.args![i]));
         }
         return Value.string(tmpl);
      },
      'err_args': (args, ctx) {
         if (args.isEmpty) return Value.voidVal();
         if (args[0].type != ValueType.Error) return Value(type: ValueType.Error, code: 4007, args: [Value.string("Error"), Value.string(typeToString(args[0].type)), Value.string("err_args")]);
         return Value(type: ValueType.Array, value: args[0].args ?? []);
      },
      'err_isError': (args, ctx) => (args.isNotEmpty && args[0].type == ValueType.Error) ? Value.number(1.0) : Value.voidVal(),

      'regex_parse': (args, ctx) {
        if (args.isEmpty) return Value.voidVal();
        String pattern = valToString(args[0]);
        String flags = args.length > 1 ? valToString(args[1]) : '';
        bool caseInsensitive = flags.contains('i');
        bool multiLine = flags.contains('m');
        try {
          return Value(
            type: ValueType.Opaque,
            label: 'RegExp',
            value: RegExp(pattern, caseSensitive: !caseInsensitive, multiLine: multiLine),
          );
        } catch (e) { return Value.voidVal(); }
      },
      'regex_match': (args, ctx) {
        if (args.length < 2) return Value.voidVal();
        String s = valToString(args[0]);
        Value p = args[1];
        if (p.type == ValueType.Opaque && p.label == 'RegExp') {
          return (p.value as RegExp).hasMatch(s) ? Value.number(1.0) : Value.voidVal();
        }
        return s.contains(valToString(p)) ? Value.number(1.0) : Value.voidVal();
      },
      'regex_replace': (args, ctx) {
        if (args.length < 3) return Value.voidVal();
        String s = valToString(args[0]);
        Value p = args[1];
        String r = valToString(args[2]);
        if (p.type == ValueType.Opaque && p.label == 'RegExp') {
          return Value.string(s.replaceAll(p.value as RegExp, r));
        }
        return Value.string(s.replaceAll(valToString(p), r));
      },
    };
  }
}
