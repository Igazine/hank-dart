import 'Types.dart';
import 'Lexer.dart';
import 'Parser.dart';
import 'Interpreter.dart';
import 'ErrorRegistry.dart';

/**
 * A Hank Host Runner.
 * Handles resource orchestration, macro resolution, and AST caching.
 * Platform-agnostic: uses the Resource model for all content retrieval.
 */
class Runner {
  final Map<String, Resource> resourceCache = {};
  final Scope coreScope = HankScope();
  final Map<int, String> localization = {};

  Runner();

  /**
   * Registers a localization map (Code -> Template).
   */
  void registerLocalization(Map<int, String> map) {
    localization.addAll(map);
  }

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
    coreScope.set(name, Value(type: ValueType.Map, value: moduleObj));
  }

  /**
   * Registers a Hank Extension and all its modules.
   */
  void registerExtension(HankExtension ext) {
    var mods = ext.getModules();
    mods.forEach((name, tasks) {
      registerModule(name, tasks);
    });
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
    if (stack.contains(resource.id)) {
      throw HankErrorRegistry.create(HankError.CircularDependency, [resource.id]);
    }

    // Reconcile with cache
    Resource activeResource = resourceCache[resource.id] ?? resource;
    if (!resourceCache.containsKey(resource.id)) {
      resourceCache[resource.id] = resource;
    }

    await activeResource.load();
    if (activeResource.content == null) {
      throw HankErrorRegistry.create(HankError.ResourceContentNotLoaded, [activeResource.id]);
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
   * Internal synchronous load for macros.
   */
  Expr _loadSync(Resource resource, List<String> stack) {
    if (resourceCache.containsKey(resource.id)) {
      Resource cached = resourceCache[resource.id]!;
      if (cached.ast != null) return cached.ast!;
    }
    if (stack.contains(resource.id)) {
      throw HankErrorRegistry.create(HankError.CircularDependency, [resource.id]);
    }

    Resource activeResource = resourceCache[resource.id] ?? resource;
    if (!resourceCache.containsKey(resource.id)) resourceCache[resource.id] = resource;

    activeResource.load(); // Kick off load
    
    if (activeResource.content == null) {
      throw HankErrorRegistry.create(HankError.ResourceContentNotLoaded, [activeResource.id]);
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

    var interpreter = Interpreter(null, coreScope, localization);
    Value scriptRes = interpreter.run(ast);

    if (scriptRes.type == ValueType.Task) {
      return interpreter.call(scriptRes, args);
    } else if (scriptRes.type == ValueType.Error) {
      return scriptRes;
    }

    throw HankErrorRegistry.create(HankError.ScriptMustBeTask);
  }
}
