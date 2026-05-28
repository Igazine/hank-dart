import 'Types.dart';
import 'Lexer.dart';
import 'Parser.dart';
import 'Interpreter.dart';

/**
 * A Hank Host Runner.
 * Handles resource orchestration, macro resolution, and AST caching.
 * Platform-agnostic: uses the Resource model for all content retrieval.
 */
class Runner {
  final Map<String, Resource> resourceCache = {};
  final Scope coreScope = HankScope();

  Runner();

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
   * Pre-loads and caches a resource for execution.
   */
  Future<Expr> load(Resource resource, [List<String> stack = const []]) async {
    // Check cache
    if (resourceCache.containsKey(resource.id)) {
      Resource cached = resourceCache[resource.id]!;
      if (cached.ast != null) return cached.ast!;
    }

    // Circular Dependency Check
    if (stack.contains(resource.id)) throw Exception('Circular Dependency: ${resource.id}');

    // Reconcile with cache
    Resource activeResource = resourceCache[resource.id] ?? resource;
    if (!resourceCache.containsKey(resource.id)) {
      resourceCache[resource.id] = resource;
    }

    await activeResource.load();
    if (activeResource.content == null) throw Exception('Resource content not loaded: ${activeResource.id}');

    List<String> newStack = List.from(stack)..add(activeResource.id);

    var lexer = Lexer(activeResource.content!);
    var parser = Parser(lexer.tokenize(), activeResource.id, (String macroPath) {
      Resource mRes = activeResource.resolve(macroPath);
      // Recursively load macro (Wait! Parser is sync, load is async).
      // For Dart, if we want sync macros, the Resource.load() must be capable of sync or we pre-load.
      // But we are following the Haxe/Go architecture.
      // Let's implement a sync-compatible path or use a temporary sync load for macros.
      return _loadSync(mRes, newStack);
    });

    Expr ast = parser.parse();
    activeResource.ast = ast;
    return ast;
  }

  /**
   * Internal synchronous load for macros.
   */
  Expr _loadSync(Resource resource, List<String> stack) {
    if (resourceCache.containsKey(resource.id)) {
      Resource cached = resourceCache[resource.id]!;
      if (cached.ast != null) return cached.ast!;
    }
    if (stack.contains(resource.id)) throw Exception('Circular Dependency: ${resource.id}');

    Resource activeResource = resourceCache[resource.id] ?? resource;
    if (!resourceCache.containsKey(resource.id)) resourceCache[resource.id] = resource;

    // This requires the resource.load() to be capable of sync execution.
    // In Dart, we'll call load() and if it returns a Future that is already completed, we are fine.
    // But since it's an abstract Future, we might have issues.
    // Host implementations for CLI should ideally provide a sync load mechanism.
    // For now, we'll try to await it but this is a sync context.
    // Let's assume the host handles sync I/O in the Resource.
    
    // NOTE: Dart's async/await can't be used in a sync function.
    // We'll trust that the host implementation of load() for CLI is effectively sync or pre-loaded.
    activeResource.load(); // Kick off load
    
    if (activeResource.content == null) {
      throw Exception('Resource content not loaded (Sync required for macros): ${activeResource.id}');
    }

    List<String> newStack = List.from(stack)..add(activeResource.id);
    var lexer = Lexer(activeResource.content!);
    var parser = Parser(lexer.tokenize(), activeResource.id, (String macroPath) {
      Resource mRes = activeResource.resolve(macroPath);
      return _loadSync(mRes, newStack);
    });

    Expr ast = parser.parse();
    activeResource.ast = ast;
    return ast;
  }

  /**
   * Removes a resource from the cache.
   */
  void unload(Resource resource) {
    resourceCache.remove(resource.id);
  }

  /**
   * Executes a Hank Resource.
   */
  Future<Value> run(Resource resource, [List<Value> args = const []]) async {
    Expr ast = await load(resource);

    var interpreter = Interpreter(null, coreScope);
    Value scriptTask = interpreter.run(ast);

    if (scriptTask.type != ValueType.Task) {
      throw Exception('Hank Error: Script must evaluate to a Task definition.');
    }

    return interpreter.call(scriptTask, args);
  }
}
