import 'Types.dart';
import 'Lexer.dart';
import 'Parser.dart';
import 'Interpreter.dart';

/**
 * A base class for HAL Host Runners in Dart.
 * Handles script loading, macro resolution, and AST caching.
 * Environment-agnostic: must be extended to provide I/O.
 */
abstract class Runner {
  final Map<String, String> pathCache = {};
  final Map<String, Expr> astCache = {};
  final Map<String, String> macroMap = {};
  final Scope coreScope = HankScope();

  Runner();

  /**
   * Reads a file from the host environment.
   */
  String readFile(String path);

  /**
   * Resolves a macro path relative to the current file.
   */
  String resolvePath(String macroPath, String baseFile);

  /**
   * Registers a set of native tasks under a module name.
   */
  void registerModule(String name, Map<String, NativeFunc> tasks) {
    Map<String, Value> moduleObj = {};
    tasks.forEach((tName, func) {
      moduleObj[tName] = Value(
        type: ValueType.Task,
        task: TaskValue(
          isNative: true,
          name: '$name.$tName',
          native: func,
        ),
      );
    });
    coreScope.set(name, Value(type: ValueType.Object, value: moduleObj));
  }

  /**
   * Pre-loads and caches a script for execution.
   */
  String load(String scriptPath) {
    String absPath = resolvePath(scriptPath, '');
    if (astCache.containsKey(absPath)) return absPath;

    _preprocess(absPath, []);

    String? content = pathCache[absPath];
    if (content == null) throw Exception('File not loaded: $absPath');

    var lexer = Lexer(content);
    var parser = Parser(lexer.tokenize(), absPath, macroMap);
    Expr ast = parser.parse();
    
    astCache[absPath] = ast;
    return absPath;
  }

  /**
   * Removes a script from the cache.
   */
  void unload(String scriptPath) {
    String absPath = resolvePath(scriptPath, '');
    astCache.remove(absPath);
    pathCache.remove(absPath);
  }

  /**
   * Executes a HAL script.
   */
  Value run(String scriptPath, [List<Value> args = const []]) {
    String absPath = load(scriptPath);
    Expr ast = astCache[absPath]!;

    var interpreter = Interpreter(null, coreScope);
    Value scriptTask = interpreter.run(ast);

    if (scriptTask.type != ValueType.Task) {
      throw Exception('Hank Error: Script must evaluate to a Task definition.');
    }

    return interpreter.call(scriptTask, args);
  }

  void _preprocess(String filePath, List<String> stack) {
    if (stack.contains(filePath)) throw Exception('Circular Dependency: $filePath');
    if (pathCache.containsKey(filePath)) return;

    String content = readFile(filePath);
    pathCache[filePath] = content;
    
    List<String> newStack = List.from(stack)..add(filePath);
    List<String> macros = _scanMacros(content);

    for (var m in macros) {
      String mPath = resolvePath(m, filePath);
      _preprocess(mPath, newStack);
      macroMap[m] = pathCache[mPath]!;
    }
  }

  List<String> _scanMacros(String content) {
    var lexer = Lexer(content);
    var tokens = lexer.tokenize();
    List<String> macros = [];
    for (int i = 0; i < tokens.length - 1; i++) {
      if (tokens[i].type == TokenType.At) {
        var next = tokens[i + 1];
        if (next.type == TokenType.String) {
          macros.add(next.literal.substring(1, next.literal.length - 1));
        } else if (next.type == TokenType.Identifier) {
          macros.add(next.literal);
        }
      }
    }
    return macros;
  }
}
