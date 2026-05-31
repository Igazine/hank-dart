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
  final int maxInstructions;

  Runner({this.maxInstructions = 0});

  /**
   * Registers a localization map (Code -> Template).
   */
  void registerLocalization(Map<int, String> map) {
    localization.addAll(map);
  }

  /**
   * Registers a set of native tasks directly into core scope.
   */
  void registerModule(Map<String, NativeFunc> tasks) {
    tasks.forEach((tName, func) {
      coreScope.set(tName, Value(
        type: ValueType.Task,
        task: TaskValue(
          isNative: true,
          name: tName,
          native: func,
        ),
      ));
    });
  }

  /**
   * Registers a Hank Extension and all its tasks.
   */
  void registerExtension(HankExtension ext) {
    registerModule(ext.getTasks());
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
    try {
      Expr ast = await load(resource);

      var interpreter = Interpreter(null, coreScope, localization: localization, maxInstructions: maxInstructions);
      Value scriptRes = interpreter.run(ast);

      if (scriptRes.type == ValueType.Task) {
        return interpreter.call(scriptRes, args);
      } else if (scriptRes.type == ValueType.Error) {
        return scriptRes;
      }

      throw HankErrorRegistry.create(HankError.ScriptMustBeTask);
    } on HankErrorValue catch (e) {
      return Value(type: ValueType.Error, code: e.code.index + 1000, args: [Value.string(e.message)]);
    } catch (e) {
      return Value(type: ValueType.Error, code: 4006, args: [Value.string(e.toString())]);
    }
  }
}
