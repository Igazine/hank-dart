import 'dart:io';
import 'package:hank/hal.dart';
import 'package:path/path.dart' as p;
import 'file_resource.dart';

void main(List<String> args) async {
  Directory current = Directory.current;
  String workspaceRoot = p.normalize(p.join(current.path, 'vendor/hank'));
  if (!Directory(workspaceRoot).existsSync()) {
    workspaceRoot = p.normalize(p.join(current.path, '../../vendor/hank'));
  }

  if (args.isEmpty) {
    await runConformance(workspaceRoot);
    return;
  }

  var runner = createRunner();
  List<Value> hankArgs = args.skip(1).map((a) => Value.string(a)).toList();

  try {
    String scriptPath = p.isAbsolute(args[0]) ? args[0] : p.join(current.path, args[0]);
    var resource = FileResource.create(scriptPath);
    Value res = await runner.run(resource, hankArgs);
    if (res.type == ValueType.Number) {
      exit((res.value as double).toInt());
    }
    exit(0);
  } catch (e) {
    String msg = e.toString();
    if (msg.contains('HANK_HALT:')) {
      exit(int.parse(msg.split(':').last));
    }
    print(msg);
    exit(1);
  }
}

Runner createRunner() {
  var runner = Runner();

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
    'type': (args, ctx) {
       String s = Platform.operatingSystem;
       if (s == 'macos') return Value.string('darwin');
       return Value.string(s);
    },
    'name': (args, ctx) => Value.string(Platform.operatingSystem),
    'arch': (args, ctx) => Value.string(Platform.version),
    'memory': (args, ctx) {
       Map<String, Value> map = {
         'total': Value.number(1024.0),
         'free': Value.number(512.0),
         'used': Value.number(512.0),
       };
       return Value(type: ValueType.Object, value: map);
    },
    'cpu': (args, ctx) => Value.number(0.0),
  });

  runner.registerModule('host', {
    'cwd': (args, ctx) => Value.string(Directory.current.path),
    'pid': (args, ctx) => Value.number(pid.toDouble()),
    'isRoot': (args, ctx) => Value.voidVal(),
  });

  runner.registerModule('runtime', {
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
           'isDir': (s.mode & 0x4000) != 0 ? Value.number(1.0) : Value.voidVal(),
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

Future<void> runConformance(String workspaceRoot) async {
  var tests = [
    'test/conformance/01_literals.hank',
    'test/conformance/02_gates.hank',
    'test/conformance/03_scoping.hank',
    'test/conformance/04_hoisting.hank',
    'test/conformance/05_params.hank',
    'test/conformance/06_macros.hank',
    'test/conformance/07_returns.hank',
    'test/conformance/08_host_args.hank',
    'test/conformance/09_deep_nesting.hank',
    'test/conformance/10_edge_cases.hank',
    'test/conformance/11_regex_parse.hank',
    'test/conformance/12_data_advanced.hank',
    'test/conformance/13_logic_module.hank',
    'test/conformance/14_syslib_hank.hank',
    'test/conformance/15_logic_eq.hank',
    'test/conformance/16_chained_assign.hank',
    'test/conformance/17_num_module.hank',
  ];

  for (var t in tests) {
    print('--- Running: $t ---');
    var runner = createRunner();
    String fullPath = p.join(workspaceRoot, t);
    var resource = FileResource.create(fullPath);
    List<Value> args = t.endsWith('08_host_args.hank') ? [Value.string('Tamas')] : [];
    try {
      await runner.run(resource, args);
    } catch (e) {
      print('Test Failed: $e');
    }
    print('--------------------\n');
  }
}
