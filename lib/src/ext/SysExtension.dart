import '../Types.dart';

class SysExtension implements HankExtension {
  @override
  String get name => "SysExtension";

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

    return {
      // host
      'host_cwd': (args, ctx) => Value.string('unknown'), // Simplified for web-safe Dart
      'host_pid': (args, ctx) => Value.number(0.0),
      'host_isRoot': (args, ctx) => Value.voidVal(),

      // os
      'os_type': (args, ctx) => Value.string('unknown'),
      'os_name': (args, ctx) => Value.string('unknown'),
      'os_arch': (args, ctx) => Value.string('unknown'),
      'os_memory': (args, ctx) => Value(type: ValueType.Map, value: {
        'total': Value.number(0.0),
        'free': Value.number(0.0),
        'used': Value.number(0.0),
      }),
      'os_cpu': (args, ctx) => Value.number(0.0),

      // fs
      'fs_exists': (args, ctx) => Value.voidVal(),
      'fs_read': (args, ctx) => Value.voidVal(),
      'fs_write': (args, ctx) => Value.voidVal(),
      'fs_deleteFile': (args, ctx) => Value.voidVal(),
      'fs_stat': (args, ctx) => Value.voidVal(),

      // proc
      'proc_run': (args, ctx) => Value.voidVal(),
    };
  }
}
