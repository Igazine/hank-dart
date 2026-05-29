import 'Types.dart';

class HankErrorRegistry {
  static final Map<HankError, String> messages = {
    HankError.UnexpectedCharacter: "Unexpected character: {0}",
    HankError.UnclosedStringLiteral: "Unclosed string literal",
    
    HankError.EmptyScript: "Syntax Error: Script is empty.",
    HankError.ExpectedMainTask: "Syntax Error: Expected main task definition (a closure or a block).",
    HankError.UnexpectedCodeOutsideMainTask: "Syntax Error: Unexpected code outside of main task. A Hank script must contain exactly one Task definition.",
    HankError.InvalidAssignmentTarget: "Invalid assignment target",
    HankError.UnexpectedToken: "Unexpected token: {0} ({1})",
    HankError.MacroRequiresString: "Syntax Error: The '@' macro strictly requires a string literal path (e.g., @ \"utils\"). Identifier shorthand is not allowed.",
    HankError.ExpectedIdentifier: "Expected identifier, found {0}",
    
    HankError.CircularDependency: "Circular Dependency: {0}",
    HankError.ResourceContentNotLoaded: "Resource content not loaded: {0}",
    HankError.ScriptMustBeTask: "Hank Error: Script must evaluate to a Task definition.",
    HankError.MacroResourceNotFound: "Macro resource not found: @{0}",
    
    HankError.TargetNotFunction: "Target is not a function: {0}",
    HankError.TooManyArguments: "Too many arguments",
    HankError.MissingRequiredParameter: "Missing required parameter: {0}",
    HankError.Halt: "HANK_HALT:{0}",
    HankError.BitwiseOutOfBounds: "Value exceeds safe integer bounds for bitwise operation: {0}",
    HankError.GenericRuntimeError: "{0}",
  };

  static HankErrorValue create(HankError code, [List<dynamic>? args, String? filename, int? line, String? lineText]) {
    String tmpl = messages[code] ?? "Unknown Error";

    if (args != null) {
      for (int i = 0; i < args.length; i++) {
        tmpl = tmpl.replaceAll('{$i}', args[i].toString());
      }
    }

    if (filename != null && line != null && lineText != null) {
      tmpl = 'ERROR: $tmpl in $filename at\n\t$line:\t$lineText';
    }

    return HankErrorValue(code, tmpl);
  }
}
