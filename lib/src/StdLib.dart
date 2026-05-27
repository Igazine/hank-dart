import 'dart:convert';
import 'Types.dart';

class StdLib {
  /**
   * Returns the recommended standard library modules.
   * Developers should register these manually on their Runner.
   */
  static Map<String, Map<String, NativeFunc>> getModules() {
    String valToString(Value v) {
      return v.toString();
    }

    Value mapAnyToHal(dynamic v) {
      if (v == null) return Value.voidVal();
      if (v is IHALSerializable) return Value.string(v.serializeHAL());
      if (v is double) return Value.number(v);
      if (v is int) return Value.number(v.toDouble());
      if (v is String) return Value.string(v);
      if (v is bool) return v ? Value.number(1.0) : Value.voidVal();
      if (v is List) return Value(type: ValueType.Array, value: v.map(mapAnyToHal).toList());
      if (v is Map) {
        Map<String, Value> obj = {};
        v.forEach((k, val) {
          obj[k.toString()] = mapAnyToHal(val);
        });
        return Value(type: ValueType.Object, value: obj);
      }
      return Value.voidVal();
    }

    dynamic mapHalToAny(Value v) {
      switch (v.type) {
        case ValueType.Number: return v.value as double;
        case ValueType.String: return v.value as String;
        case ValueType.Array: return (v.value as List<Value>).map(mapHalToAny).toList();
        case ValueType.Object:
          Map<String, dynamic> obj = {};
          (v.value as Map<String, Value>).forEach((k, val) {
            obj[k] = mapHalToAny(val);
          });
          return obj;
        default: return null;
      }
    }

    return {
      'log': {
        'print': (args, ctx) { print(args.map(valToString).join(' ')); return Value.voidVal(); },
        'error': (args, ctx) { print('[ERROR] ' + args.map(valToString).join(' ')); return Value.voidVal(); },
        'warn': (args, ctx) { print('[WARN] ' + args.map(valToString).join(' ')); return Value.voidVal(); },
      },
      'runtime': {
        'halt': (args, ctx) {
          int code = 0;
          if (args.length > 0 && args[0].type == ValueType.Number) code = (args[0].value as double).toInt();
          throw Exception('HAL_HALT:$code'); // Demo app should catch this
        },
        'elapsedTime': (args, ctx) => Value.number(0.0),
      },
      'env': {
        'get': (args, ctx) => Value.voidVal(),
        'set': (args, ctx) => Value.voidVal(),
        'keys': (args, ctx) => Value(type: ValueType.Array, value: <Value>[]),
      },
      'str': {
        'length': (args, ctx) => args.isEmpty ? Value.voidVal() : Value.number(valToString(args[0]).length.toDouble()),
        'format': (args, ctx) {
          if (args.isEmpty) return Value.voidVal();
          String res = valToString(args[0]);
          for (int i = 1; i < args.length; i++) {
            res = res.replaceAll('%$i', valToString(args[i]));
          }
          return Value.string(res);
        },
        'concat': (args, ctx) => Value.string(args.map(valToString).join('')),
        'trim': (args, ctx) => args.isEmpty ? Value.voidVal() : Value.string(valToString(args[0]).trim()),
      },
      'math': {
        'add': (args, ctx) => Value.number(args.fold(0.0, (sum, a) => sum + (a.type == ValueType.Number ? (a.value as double) : 0.0))),
        'sub': (args, ctx) => (args.length < 2) ? Value.voidVal() : Value.number((args[0].value as double) - (args[1].value as double)),
        'mul': (args, ctx) => (args.isEmpty) ? Value.number(0.0) : Value.number(args.fold(1.0, (res, a) => res * (a.type == ValueType.Number ? (a.value as double) : 1.0))),
        'div': (args, ctx) => (args.length < 2 || (args[1].value as double) == 0) ? Value.voidVal() : Value.number((args[0].value as double) / (args[1].value as double)),
        'gt': (args, ctx) => (args.length < 2) ? Value.voidVal() : ((args[0].value as double) > (args[1].value as double) ? Value.number(1.0) : Value.voidVal()),
        'lt': (args, ctx) => (args.length < 2) ? Value.voidVal() : ((args[0].value as double) < (args[1].value as double) ? Value.number(1.0) : Value.voidVal()),
        'eq': (args, ctx) => (args.length < 2) ? Value.voidVal() : (valToString(args[0]) == valToString(args[1]) ? Value.number(1.0) : Value.voidVal()),
      },
      'logic': {
        'and': (args, ctx) {
          if (args.isEmpty) return Value.voidVal();
          Value last = Value.voidVal();
          for (var a in args) {
            if (a.type == ValueType.Void) return Value.voidVal();
            last = a;
          }
          return last;
        },
        'or': (args, ctx) {
          for (var a in args) {
            if (a.type != ValueType.Void) return a;
          }
          return Value.voidVal();
        },
      },
      'arr': {
        'length': (args, ctx) => (args.isNotEmpty && args[0].type == ValueType.Array) ? Value.number((args[0].value as List).length.toDouble()) : Value.voidVal(),
        'get': (args, ctx) {
           if (args.length < 2 || args[0].type != ValueType.Array || args[1].type != ValueType.Number) return Value.voidVal();
           List<Value> l = args[0].value;
           int idx = (args[1].value as double).toInt();
           if (idx < 0 || idx >= l.length) return Value.voidVal();
           return l[idx];
        },
        'push': (args, ctx) {
           if (args.length >= 2 && args[0].type == ValueType.Array) {
             (args[0].value as List<Value>).add(args[1]);
           }
           return Value.voidVal();
        },
        'pop': (args, ctx) {
           if (args.isNotEmpty && args[0].type == ValueType.Array) {
             List<Value> l = args[0].value;
             if (l.isNotEmpty) return l.removeLast();
           }
           return Value.voidVal();
        },
        'each': (args, ctx) {
           if (args.length >= 2 && args[0].type == ValueType.Array && args[1].type == ValueType.Task) {
             List<Value> items = List.from(args[0].value as List<Value>);
             for (int i = 0; i < items.length; i++) {
               ctx.call(args[1], [items[i], Value.number(i.toDouble())]);
             }
           }
           return Value.voidVal();
        },
      },
      'obj': {
        'get': (args, ctx) => (args.length >= 2 && args[0].type == ValueType.Object) ? ((args[0].value as Map<String, Value>)[valToString(args[1])] ?? Value.voidVal()) : Value.voidVal(),
        'keys': (args, ctx) => (args.isNotEmpty && args[0].type == ValueType.Object) ? Value(type: ValueType.Array, value: (args[0].value as Map<String, Value>).keys.map((k) => Value.string(k)).toList()) : Value.voidVal(),
        'values': (args, ctx) => (args.isNotEmpty && args[0].type == ValueType.Object) ? Value(type: ValueType.Array, value: (args[0].value as Map<String, Value>).values.toList()) : Value.voidVal(),
      },
      'json': {
        'parse': (args, ctx) {
          if (args.isEmpty) return Value.voidVal();
          try {
            return mapAnyToHal(jsonDecode(valToString(args[0])));
          } catch (e) {
            return Value.voidVal();
          }
        },
        'stringify': (args, ctx) => (args.isNotEmpty) ? Value.string(jsonEncode(mapHalToAny(args[0]))) : Value.voidVal(),
      },
      'regex': {
        'parse': (args, ctx) {
          if (args.isEmpty) return Value.voidVal();
          String pattern = valToString(args[0]);
          String flags = args.length > 1 ? valToString(args[1]) : '';
          bool caseInsensitive = flags.contains('i');
          bool multiLine = flags.contains('m');
          try {
            return Value(
              type: ValueType.Regex,
              pattern: pattern,
              flags: flags,
              engine: RegExp(pattern, caseSensitive: !caseInsensitive, multiLine: multiLine),
            );
          } catch (e) { return Value.voidVal(); }
        },
        'match': (args, ctx) {
          if (args.length < 2) return Value.voidVal();
          String s = valToString(args[0]);
          Value p = args[1];
          if (p.type == ValueType.Regex) {
            return (p.engine?.hasMatch(s) ?? false) ? Value.number(1.0) : Value.voidVal();
          }
          return s.contains(valToString(p)) ? Value.number(1.0) : Value.voidVal();
        },
        'replace': (args, ctx) {
          if (args.length < 3) return Value.voidVal();
          String s = valToString(args[0]);
          Value p = args[1];
          String r = valToString(args[2]);
          if (p.type == ValueType.Regex && p.engine != null) {
            return Value.string(s.replaceAll(p.engine!, r));
          }
          return Value.string(s.replaceAll(valToString(p), r));
        },
      }
    };
  }
}
