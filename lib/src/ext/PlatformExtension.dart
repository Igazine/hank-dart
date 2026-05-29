import '../Types.dart';
import '../ErrorRegistry.dart';

class PlatformExtension implements HankExtension {
  @override
  String get name => "PlatformExtension";

  static const double _SAFE_INT_MAX = 9007199254740991.0;

  static int _checkSafeInt(double n) {
    if (n.abs() > _SAFE_INT_MAX || !n.isFinite) {
      throw HankErrorRegistry.create(HankError.BitwiseOutOfBounds, [n]);
    }
    return n.toInt();
  }

  static double _fromSafeInt(int n) {
    double f = n.toDouble();
    if (f.abs() > _SAFE_INT_MAX) {
      throw HankErrorRegistry.create(HankError.BitwiseOutOfBounds, [f]);
    }
    return f;
  }

  @override
  Map<String, Map<String, NativeFunc>> getModules() {
    return {
      'bin': {
        'and': (args, ctx) {
          double a = args.length > 0 && args[0].type == ValueType.Number ? args[0].value as double : 0.0;
          double b = args.length > 1 && args[1].type == ValueType.Number ? args[1].value as double : 0.0;
          return Value.number(_fromSafeInt(_checkSafeInt(a) & _checkSafeInt(b)));
        },
        'or': (args, ctx) {
          double a = args.length > 0 && args[0].type == ValueType.Number ? args[0].value as double : 0.0;
          double b = args.length > 1 && args[1].type == ValueType.Number ? args[1].value as double : 0.0;
          return Value.number(_fromSafeInt(_checkSafeInt(a) | _checkSafeInt(b)));
        },
        'xor': (args, ctx) {
          double a = args.length > 0 && args[0].type == ValueType.Number ? args[0].value as double : 0.0;
          double b = args.length > 1 && args[1].type == ValueType.Number ? args[1].value as double : 0.0;
          return Value.number(_fromSafeInt(_checkSafeInt(a) ^ _checkSafeInt(b)));
        },
        'not': (args, ctx) {
          double a = args.length > 0 && args[0].type == ValueType.Number ? args[0].value as double : 0.0;
          return Value.number(_fromSafeInt(~_checkSafeInt(a)));
        },
        'shiftL': (args, ctx) {
          double a = args.length > 0 && args[0].type == ValueType.Number ? args[0].value as double : 0.0;
          double b = args.length > 1 && args[1].type == ValueType.Number ? args[1].value as double : 0.0;
          return Value.number(_fromSafeInt(_checkSafeInt(a) << b.toInt()));
        },
        'shiftR': (args, ctx) {
          double a = args.length > 0 && args[0].type == ValueType.Number ? args[0].value as double : 0.0;
          double b = args.length > 1 && args[1].type == ValueType.Number ? args[1].value as double : 0.0;
          return Value.number(_fromSafeInt(_checkSafeInt(a) >> b.toInt()));
        },
      }
    };
  }
}
