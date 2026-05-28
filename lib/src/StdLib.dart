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
      if (v is IHankSerializable) return Value.string(v.serializeHank());
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

    bool hasOpaque(Value v) {
      if (v.type == ValueType.Opaque) return true;
      if (v.type == ValueType.Array) {
        return (v.value as List<Value>).any(hasOpaque);
      }
      if (v.type == ValueType.Object) {
        return (v.value as Map<String, Value>).values.any(hasOpaque);
      }
      return false;
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

    bool halEquals(Value a, Value b) {
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
            if (!halEquals(l1[i], l2[i])) return false;
          }
          return true;
        case ValueType.Object:
          Map<String, Value> m1 = a.value;
          Map<String, Value> m2 = b.value;
          if (m1.length != m2.length) return false;
          for (var key in m1.keys) {
            if (!m2.containsKey(key) || !halEquals(m1[key]!, m2[key]!)) return false;
          }
          return true;
        case ValueType.Opaque:
          return a.label == b.label && a.value == b.value;
        default: return false;
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
          throw Exception('HANK_HALT:$code');
        },
        'elapsedTime': (args, ctx) => Value.number(0.0),
        'signal': (args, ctx) {
          if (args.isNotEmpty) print('[SIGNAL] ${valToString(args[0])}');
          return Value.voidVal();
        },
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
        'eq': (args, ctx) => (args.length < 2) ? Value.voidVal() : (halEquals(args[0], args[1]) ? Value.number(1.0) : Value.voidVal()),
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
        'eq': (args, ctx) => (args.length < 2) ? Value.voidVal() : (halEquals(args[0], args[1]) ? Value.number(1.0) : Value.voidVal()),
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
        'stringify': (args, ctx) {
          if (args.isEmpty) return Value.voidVal();
          if (hasOpaque(args[0])) return Value.voidVal();
          try {
            return Value.string(jsonEncode(mapHalToAny(args[0])));
          } catch (e) {
            return Value.voidVal();
          }
        },
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
              type: ValueType.Opaque,
              label: 'RegExp',
              value: RegExp(pattern, caseSensitive: !caseInsensitive, multiLine: multiLine),
            );
          } catch (e) { return Value.voidVal(); }
        },
        'match': (args, ctx) {
          if (args.length < 2) return Value.voidVal();
          String s = valToString(args[0]);
          Value p = args[1];
          if (p.type == ValueType.Opaque && p.label == 'RegExp') {
            return (p.value as RegExp).hasMatch(s) ? Value.number(1.0) : Value.voidVal();
          }
          return s.contains(valToString(p)) ? Value.number(1.0) : Value.voidVal();
        },
        'replace': (args, ctx) {
          if (args.length < 3) return Value.voidVal();
          String s = valToString(args[0]);
          Value p = args[1];
          String r = valToString(args[2]);
          if (p.type == ValueType.Opaque && p.label == 'RegExp') {
            return Value.string(s.replaceAll(p.value as RegExp, r));
          }
          return Value.string(s.replaceAll(valToString(p), r));
        },
      }
    };
  }
}
