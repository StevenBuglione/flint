/++
Interim conformance copy of `flint.engine.aot.mapping` (docs/spring/aot-contract.md section 4.5,
contract 1), deleted when framework-core's `flint:engine-aot` lands.

Interim additions requested from flint-aot (not yet in contract 1): `HandlerMapping.beanType` and
`typeAnnotations` (class-level merged annotations, for @CrossOrigin combination), and
`ExceptionHandlerSpec.adviceAssignableTypes`, `adviceAnnotations`, `produces`.
+/
module flint.engine.aot.mapping;

import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : MergedAnnotation, MethodDescriptor;

@safe:

///
enum ArgumentKind
{
    pathVariable,
    requestParam,
    requestHeader,
    requestBody,
    cookieValue,
    modelAttribute,
    byType
}

///
struct ArgumentSpec
{
    ArgumentKind kind; ///
    string name; /// the attribute's name, else the D parameter name
    string type; /// the parameter's fully qualified type
    bool required; ///
    string defaultValue; /// ValueConstants.DEFAULT_NONE when absent
    bool validate; /// @Valid or @Validated on the parameter
    MergedAnnotation[] annotations; ///
}

///
interface HandlerArguments
{
    /// Resolved and converted to `ArgumentSpec.type`.
    Any get(size_t index);
}

///
alias HandlerInvoker = void function(Object bean, HandlerArguments arguments, ref Any result) @safe;

///
struct HandlerMapping
{
    string bean; /// bean name of the controller
    string[] paths; /// class and method paths already combined
    string[] methods; /// HTTP methods; empty = all
    string[] params; ///
    string[] headers; ///
    string[] consumes; ///
    string[] produces; ///
    ArgumentSpec[] arguments; ///
    string returnType; ///
    bool responseBody; ///
    int responseStatus; /// @ResponseStatus code, 0 when absent
    string reason; ///
    const(MethodDescriptor)* method; ///
    HandlerInvoker invoke; ///
    string source; ///
    // Interim additions (requested, not in contract 1):
    string beanType; /// fully qualified controller type
    MergedAnnotation[] typeAnnotations; /// class-level merged annotations
}

///
alias ExceptionInvoker = void function(Object bean, Exception exception, HandlerArguments arguments,
        ref Any result) @safe;

///
struct ExceptionHandlerSpec
{
    string bean; ///
    string[] exceptionTypes; ///
    bool advice; ///
    string[] adviceBasePackages; ///
    ArgumentSpec[] arguments; ///
    string returnType; ///
    bool responseBody; ///
    int responseStatus; ///
    ExceptionInvoker invoke; ///
    string source; ///
    // Interim additions (requested, not in contract 1):
    string beanType; ///
    string[] adviceAssignableTypes; ///
    string[] adviceAnnotations; ///
    string[] produces; ///
    string reason; ///
}
