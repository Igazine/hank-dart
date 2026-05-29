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

  // 1. Register StdLib (Pure)
  runner.registerExtension(new StdLib());

  // 2. Register Extensions (Batteries included, but disconnected)
  runner.registerExtension(new PlatformExtension());
  runner.registerExtension(new SysExtension());

  return runner;
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
    // 'test/conformance/14_syslib_hank.hank', // MOVED to extensions
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

  // Extension Tests
  var extTests = [
    'test/extensions/sys.hank',
    'test/extensions/platform_bin.hank'
  ];

  for (var t in extTests) {
    print('--- Running Extension Test: $t ---');
    var runner = createRunner();
    String fullPath = p.join(workspaceRoot, t);
    var resource = FileResource.create(fullPath);
    try {
      await runner.run(resource, []);
    } catch (e) {
      print('Extension Test Failed: $e');
    }
    print('--------------------\n');
  }
}
