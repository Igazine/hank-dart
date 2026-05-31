import '../Types.dart';
import '../ErrorRegistry.dart';

class PlatformExtension implements HankExtension {
  @override
  String get name => "PlatformExtension";

  static const double _SAFE_INT_MAX = 9007199254740991.0;

  static int _checkSafeInt(double n, String taskName) {
    if (n.abs() > _SAFE_INT_MAX || !n.isFinite) {
      throw Value(type: ValueType.Error, code: 4005, args: [Value.number(n), Value.string(taskName)]);
    }
    return n.toInt();
  }

  static double _fromSafeInt(int n, String taskName) {
    double f = n.toDouble();
    if (f.abs() > _SAFE_INT_MAX) {
      throw Value(type: ValueType.Error, code: 4005, args: [Value.number(f), Value.string(taskName)]);
    }
    return f;
  }

  @override
  Map<String, NativeFunc> getTasks() {
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

    return {
      'bin_and': (args, ctx) {
        if (args.length < 2) return Value.voidVal();
        if (args[0].type != ValueType.Number) return Value(type: ValueType.Error, code: 4007, args: [Value.string("Number"), Value.string(typeToString(args[0].type)), Value.string("bin_and")]);
        if (args[1].type != ValueType.Number) return Value(type: ValueType.Error, code: 4007, args: [Value.string("Number"), Value.string(typeToString(args[1].type)), Value.string("bin_and")]);
        double a = args[0].value as double;
        double b = args[1].value as double;
        return Value.number(_fromSafeInt(_checkSafeInt(a, "bin_and") & _checkSafeInt(b, "bin_and"), "bin_and"));
      },
      'bin_or': (args, ctx) {
        if (args.length < 2) return Value.voidVal();
        if (args[0].type != ValueType.Number) return Value(type: ValueType.Error, code: 4007, args: [Value.string("Number"), Value.string(typeToString(args[0].type)), Value.string("bin_or")]);
        if (args[1].type != ValueType.Number) return Value(type: ValueType.Error, code: 4007, args: [Value.string("Number"), Value.string(typeToString(args[1].type)), Value.string("bin_or")]);
        double a = args[0].value as double;
        double b = args[1].value as double;
        return Value.number(_fromSafeInt(_checkSafeInt(a, "bin_or") | _checkSafeInt(b, "bin_or"), "bin_or"));
      },
      'bin_xor': (args, ctx) {
        if (args.length < 2) return Value.voidVal();
        if (args[0].type != ValueType.Number) return Value(type: ValueType.Error, code: 4007, args: [Value.string("Number"), Value.string(typeToString(args[0].type)), Value.string("bin_xor")]);
        if (args[1].type != ValueType.Number) return Value(type: ValueType.Error, code: 4007, args: [Value.string("Number"), Value.string(typeToString(args[1].type)), Value.string("bin_xor")]);
        double a = args[0].value as double;
        double b = args[1].value as double;
        return Value.number(_fromSafeInt(_checkSafeInt(a, "bin_xor") ^ _checkSafeInt(b, "bin_xor"), "bin_xor"));
      },
      'bin_not': (args, ctx) {
        if (args.isEmpty) return Value.voidVal();
        if (args[0].type != ValueType.Number) return Value(type: ValueType.Error, code: 4007, args: [Value.string("Number"), Value.string(typeToString(args[0].type)), Value.string("bin_not")]);
        double a = args[0].value as double;
        return Value.number(_fromSafeInt(~_checkSafeInt(a, "bin_not"), "bin_not"));
      },
      'bin_shiftL': (args, ctx) {
        if (args.length < 2) return Value.voidVal();
        if (args[0].type != ValueType.Number || args[1].type != ValueType.Number) return Value(type: ValueType.Error, code: 4007, args: [Value.string("Number"), Value.string(typeToString(args[0].type)), Value.string("bin_shiftL")]);
        double a = args[0].value as double;
        double b = args[1].value as double;
        return Value.number(_fromSafeInt(_checkSafeInt(a, "bin_shiftL") << b.toInt(), "bin_shiftL"));
      },
      'bin_shiftR': (args, ctx) {
        if (args.length < 2) return Value.voidVal();
        if (args[0].type != ValueType.Number || args[1].type != ValueType.Number) return Value(type: ValueType.Error, code: 4007, args: [Value.string("Number"), Value.string(typeToString(args[0].type)), Value.string("bin_shiftR")]);
        double a = args[0].value as double;
        double b = args[1].value as double;
        return Value.number(_fromSafeInt(_checkSafeInt(a, "bin_shiftR") >> b.toInt(), "bin_shiftR"));
      },
    };
  }
}
