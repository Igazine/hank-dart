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
          Map<String, Value> obj = {};
          obj['total'] = Value.number(0);
          obj['free'] = Value.number(0);
          obj['used'] = Value.number(0);
          return Value(type: ValueType.Object, value: obj);
        },
        'cpu': (args, ctx) => Value.number(0.0)
      },
      'fs': {
        'exists': (args, ctx) => File(valToString(args[0])).existsSync() ? Value.number(1.0) : Value.voidVal(),
        'read': (args, ctx) {
          try {
            return Value.string(File(valToString(args[0])).readAsStringSync());
          } catch (e) { return Value.voidVal(); }
        },
        'write': (args, ctx) {
          try {
            File(valToString(args[0])).writeAsStringSync(valToString(args[1]));
            return Value.number(1.0);
          } catch (e) { return Value.voidVal(); }
        },
        'deleteFile': (args, ctx) {
          try {
            File(valToString(args[0])).deleteSync();
            return Value.number(1.0);
          } catch (e) { return Value.voidVal(); }
        },
        'stat': (args, ctx) {
          try {
            var s = File(valToString(args[0])).statSync();
            Map<String, Value> obj = {};
            obj['size'] = Value.number(s.size.toDouble());
            obj['mtime'] = Value.number(s.modified.millisecondsSinceEpoch.toDouble());
            obj['isDir'] = s.type == FileSystemEntityType.directory ? Value.number(1.0) : Value.voidVal();
            return Value(type: ValueType.Object, value: obj);
          } catch (e) { return Value.voidVal(); }
        }
      },
      'proc': {
        'run': (args, ctx) {
          try {
            String cmd = valToString(args[0]);
            List<String> cmdArgs = [];
            if (args.length > 1 && args[1].type == ValueType.Array) {
              cmdArgs = (args[1].value as List<Value>).map((a) => valToString(a)).toList();
            }
            var res = Process.runSync(cmd, cmdArgs);
            Map<String, Value> obj = {};
            obj['code'] = Value.number(res.exitCode.toDouble());
            obj['stdout'] = Value.string(res.stdout.toString());
            obj['stderr'] = Value.string(res.stderr.toString());
            return Value(type: ValueType.Object, value: obj);
          } catch (e) { return Value.voidVal(); }
        }
      }
    };
  }
}
