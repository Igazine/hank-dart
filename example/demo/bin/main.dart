import 'dart:io';
import 'package:hal/hal.dart';
import 'package:path/path.dart' as p;

class DemoRunner extends Runner {
  @override
  String readFile(String path) {
    return File(path).readAsStringSync();
  }

  @override
  String resolvePath(String macroPath, String baseFile) {
    if (p.isAbsolute(macroPath)) return p.canonicalize(macroPath);
    
    String baseDir = baseFile.isEmpty ? Directory.current.path : p.dirname(baseFile);
    String joined = p.normalize(p.join(baseDir, macroPath));
    
    if (p.extension(joined).isEmpty) {
      if (File('$joined.hal').existsSync()) return p.canonicalize('$joined.hal');
    }
    return p.canonicalize(joined);
  }
}

void main(List<String> args) {
  Directory current = Directory.current;
  String workspaceRoot = p.normalize(p.join(current.path, '../../vendor/hal'));

  if (args.isEmpty) {
    runConformance(workspaceRoot);
    return;
  }

  var runner = createRunner();
  List<Value> halArgs = args.skip(1).map((a) => Value.string(a)).toList();

  try {
    Value res = runner.run(args[0], halArgs);
    if (res.type == ValueType.Number) {
      exit((res.value as double).toInt());
    }
    exit(0);
  } catch (e) {
    String msg = e.toString();
    if (msg.contains('HAL_HALT:')) {
      exit(int.parse(msg.split(':').last));
    }
    print(msg);
    exit(1);
  }
}

Runner createRunner() {
  var runner = DemoRunner();

  // 1. Register StdLib (Optional)
  var std = StdLib.getModules();
  std.forEach((name, tasks) {
    runner.registerModule(name, tasks);
  });

  // 2. Register example SYSLIB
  registerSyslib(runner);

  return runner;
}

void registerSyslib(Runner runner) {
  runner.registerModule('os', {
    'type': (args, ctx) => Value.string(Platform.operatingSystem),
    'name': (args, ctx) => Value.string(Platform.operatingSystem),
    'arch': (args, ctx) => Value.string(Platform.version),
    'memory': (args, ctx) {
       Map<String, Value> map = {
         'total': Value.number(1024.0),
         'free': Value.number(512.0),
       };
       return Value(type: ValueType.Object, value: map);
    },
    'cpu': (args, ctx) => Value.number(0.0),
  });

  runner.registerModule('host', {
    'cwd': (args, ctx) => Value.string(Directory.current.path),
    'pid': (args, ctx) => Value.number(pid.toDouble()),
    'isRoot': (args, ctx) => Value.voidVal(), // Dart doesn't have a direct isRoot
    'signal': (args, ctx) {
      if (args.isNotEmpty) print('[SIGNAL] ${args[0].toString()}');
      return Value.voidVal();
    }
  });

  runner.registerModule('fs', {
    'exists': (args, ctx) => (args.isNotEmpty && File(args[0].toString()).existsSync()) ? Value.number(1.0) : Value.voidVal(),
    'read': (args, ctx) {
       try {
         return Value.string(File(args[0].toString()).readAsStringSync());
       } catch (e) { return Value.voidVal(); }
    },
    'write': (args, ctx) {
       try {
         File(args[0].toString()).writeAsStringSync(args[1].toString());
         return Value.number(1.0);
       } catch (e) { return Value.voidVal(); }
    },
    'deleteFile': (args, ctx) {
       try {
         File(args[0].toString()).deleteSync();
         return Value.number(1.0);
       } catch (e) { return Value.voidVal(); }
    },
    'stat': (args, ctx) {
       try {
         var f = File(args[0].toString());
         var s = f.statSync();
         Map<String, Value> map = {
           'size': Value.number(s.size.toDouble()),
           'mtime': Value.number(s.modified.millisecondsSinceEpoch.toDouble()),
           'isDir': s.type == FileSystemEntityType.directory ? Value.number(1.0) : Value.voidVal(),
         };
         return Value(type: ValueType.Object, value: map);
       } catch (e) { return Value.voidVal(); }
    }
  });

  runner.registerModule('proc', {
    'run': (args, ctx) {
       try {
         String cmd = args[0].toString();
         List<String> cmdArgs = [];
         if (args.length > 1 && args[1].type == ValueType.Array) {
           cmdArgs = (args[1].value as List<Value>).map((v) => v.toString()).toList();
         }
         var res = Process.runSync(cmd, cmdArgs);
         Map<String, Value> map = {
           'code': Value.number(res.exitCode.toDouble()),
           'stdout': Value.string(res.stdout.toString()),
           'stderr': Value.string(res.stderr.toString()),
         };
         return Value(type: ValueType.Object, value: map);
       } catch (e) { return Value.voidVal(); }
    }
  });
}

void runConformance(String workspaceRoot) {
  var tests = [
    'test/conformance/01_literals.hal',
    'test/conformance/02_gates.hal',
    'test/conformance/03_scoping.hal',
    'test/conformance/04_hoisting.hal',
    'test/conformance/05_params.hal',
    'test/conformance/06_macros.hal',
    'test/conformance/07_returns.hal',
    'test/conformance/08_host_args.hal',
    'test/conformance/09_deep_nesting.hal',
    'test/conformance/10_edge_cases.hal',
    'test/conformance/11_regex_parse.hal',
    'test/conformance/12_data_advanced.hal',
    'test/conformance/13_logic_module.hal',
    'test/conformance/14_syslib_hank.hal',
  ];

  for (var t in tests) {
    print('--- Running: $t ---');
    var runner = createRunner();
    String path = p.join(workspaceRoot, t);
    List<Value> args = t.endsWith('08_host_args.hal') ? [Value.string('Tamas')] : [];
    try {
      runner.run(path, args);
    } catch (e) {
      print('Test Failed: $e');
    }
    print('--------------------\n');
  }
}
