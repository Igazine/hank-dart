import 'dart:io';
import '../Types.dart';

class SysExtension implements HankExtension {
  @override
  String get name => "SysExtension";

  @override
  Map<String, Map<String, NativeFunc>> getModules() {
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
      'host': {
        'cwd': (args, ctx) => Value.string(Directory.current.path),
        'isRoot': (args, ctx) => Platform.isLinux || Platform.isMacOS ? (Process.runSync('id', ['-u']).stdout.toString().trim() == '0' ? Value.number(1.0) : Value.voidVal()) : Value.voidVal(),
        'pid': (args, ctx) => Value.number(pid.toDouble())
      },
      'os': {
        'type': (args, ctx) {
          if (Platform.isWindows) return Value.string('windows');
          if (Platform.isLinux) return Value.string('linux');
          if (Platform.isMacOS) return Value.string('darwin');
          return Value.string('unknown');
        },
        'name': (args, ctx) => Value.string(Platform.operatingSystem),
        'arch': (args, ctx) => Value.string(Platform.version), // Version contains arch
        'memory': (args, ctx) {
          Map<String, Value> map = {};
          map['total'] = Value.number(0);
          map['free'] = Value.number(0);
          map['used'] = Value.number(0);
          return Value(type: ValueType.Map, value: map);
        },
        'cpu': (args, ctx) => Value.number(0.0)
      },
      'fs': {
        'exists': (args, ctx) {
           if (args.isEmpty) return Value.voidVal();
           if (args[0].type != ValueType.String) {
             return Value(type: ValueType.Error, code: 4007, args: [Value.string("String"), Value.string(typeToString(args[0].type)), Value.string("fs.exists")]);
           }
           return File(valToString(args[0])).existsSync() ? Value.number(1.0) : Value.voidVal();
        },
        'read': (args, ctx) {
          if (args.isEmpty) return Value.voidVal();
          if (args[0].type != ValueType.String) {
            return Value(type: ValueType.Error, code: 4007, args: [Value.string("String"), Value.string(typeToString(args[0].type)), Value.string("fs.read")]);
          }
          try {
            return Value.string(File(valToString(args[0])).readAsStringSync());
          } catch (e) { return Value.voidVal(); }
        },
        'write': (args, ctx) {
          if (args.length < 2) return Value.voidVal();
          if (args[0].type != ValueType.String || args[1].type != ValueType.String) {
            Value faulty = args[0].type != ValueType.String ? args[0] : args[1];
            return Value(type: ValueType.Error, code: 4007, args: [Value.string("String"), Value.string(typeToString(faulty.type)), Value.string("fs.write")]);
          }
          try {
            File(valToString(args[0])).writeAsStringSync(valToString(args[1]));
            return Value.number(1.0);
          } catch (e) { return Value.voidVal(); }
        },
        'deleteFile': (args, ctx) {
          if (args.isEmpty) return Value.voidVal();
          if (args[0].type != ValueType.String) {
            return Value(type: ValueType.Error, code: 4007, args: [Value.string("String"), Value.string(typeToString(args[0].type)), Value.string("fs.deleteFile")]);
          }
          try {
            File(valToString(args[0])).deleteSync();
            return Value.number(1.0);
          } catch (e) { return Value.voidVal(); }
        },
        'stat': (args, ctx) {
          if (args.isEmpty) return Value.voidVal();
          if (args[0].type != ValueType.String) {
            return Value(type: ValueType.Error, code: 4007, args: [Value.string("String"), Value.string(typeToString(args[0].type)), Value.string("fs.stat")]);
          }
          try {
            var s = File(valToString(args[0])).statSync();
            Map<String, Value> map = {};
            map['size'] = Value.number(s.size.toDouble());
            map['mtime'] = Value.number(s.modified.millisecondsSinceEpoch.toDouble());
            map['isDir'] = s.type == FileSystemEntityType.directory ? Value.number(1.0) : Value.voidVal();
            return Value(type: ValueType.Map, value: map);
          } catch (e) { return Value.voidVal(); }
        }
      },
      'proc': {
        'run': (args, ctx) {
          if (args.isEmpty) return Value.voidVal();
          if (args[0].type != ValueType.String) {
            return Value(type: ValueType.Error, code: 4007, args: [Value.string("String"), Value.string(typeToString(args[0].type)), Value.string("proc.run")]);
          }
          try {
            String cmd = valToString(args[0]);
            List<String> cmdArgs = [];
            if (args.length > 1 && args[1].type == ValueType.Array) {
              cmdArgs = (args[1].value as List<Value>).map((a) => valToString(a)).toList();
            }
            var res = Process.runSync(cmd, cmdArgs);
            Map<String, Value> map = {};
            map['code'] = Value.number(res.exitCode.toDouble());
            map['stdout'] = Value.string(res.stdout.toString());
            map['stderr'] = Value.string(res.stderr.toString());
            return Value(type: ValueType.Map, value: map);
          } catch (e) { return Value.voidVal(); }
        }
      }
    };
  }
}
