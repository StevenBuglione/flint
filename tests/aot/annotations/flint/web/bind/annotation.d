/// Fixture for Flint AOT tests: `org.springframework.web.bind.annotation`.
module flint.web.bind.annotation;

import flint.core.annotation : AliasFor, ClassRef;
import flint.stereotype : Controller;

@safe:

/// HTTP methods.
enum RequestMethod
{
    GET,
    HEAD,
    POST,
    PUT,
    PATCH,
    DELETE,
    OPTIONS,
    TRACE
}

/// `ValueConstants.DEFAULT_NONE`.
enum DEFAULT_NONE = "\n\t\t\n\t\t\n\n\t\t\t\t\n";

/// `@ResponseBody`.
struct ResponseBody
{
}

/// `@RestController`.
@Controller @ResponseBody struct RestController
{
    /// Bean name.
    @AliasFor(annotation: ClassRef("flint.stereotype.Controller")) string value;
}

/// `@RequestMapping`.
struct RequestMapping
{
    /// Mapping name.
    string name;
    /// Alias of `path`.
    @AliasFor("path") string[] value;
    /// Paths.
    @AliasFor("value") string[] path;
    /// HTTP methods.
    RequestMethod[] method;
    /// Parameter conditions.
    string[] params;
    /// Header conditions.
    string[] headers;
    /// Consumable media types.
    string[] consumes;
    /// Producible media types.
    string[] produces;

    /// Java's single-value form: `@RequestMapping("x")` (aot-contract.md section 2, R2.1).
    static RequestMapping opCall(string value, string name = null, string[] path = null, RequestMethod[] method = null, string[] params = null, string[] headers = null, string[] consumes = null, string[] produces = null)
    {
        RequestMapping result;
        result.value = [value];
        result.name = name;
        result.path = path;
        result.method = method;
        result.params = params;
        result.headers = headers;
        result.consumes = consumes;
        result.produces = produces;
        return result;
    }

    /// The array form, and the named-attribute form.
    static RequestMapping opCall(string[] value = null, string name = null, string[] path = null, RequestMethod[] method = null, string[] params = null, string[] headers = null, string[] consumes = null, string[] produces = null)
    {
        RequestMapping result;
        result.value = value;
        result.name = name;
        result.path = path;
        result.method = method;
        result.params = params;
        result.headers = headers;
        result.consumes = consumes;
        result.produces = produces;
        return result;
    }
}

/// `@GetMapping`.
@RequestMapping(method: [RequestMethod.GET]) struct GetMapping
{
    /// Alias of `RequestMapping.path`.
    @AliasFor(annotation: ClassRef("flint.web.bind.annotation.RequestMapping")) string[] value;
    /// Alias of `RequestMapping.path`.
    @AliasFor(annotation: ClassRef("flint.web.bind.annotation.RequestMapping")) string[] path;
    /// Producible media types.
    @AliasFor(annotation: ClassRef("flint.web.bind.annotation.RequestMapping")) string[] produces;

    /// Java's single-value form: `@GetMapping("x")` (aot-contract.md section 2, R2.1).
    static GetMapping opCall(string value, string[] path = null, string[] produces = null)
    {
        GetMapping result;
        result.value = [value];
        result.path = path;
        result.produces = produces;
        return result;
    }

    /// The array form, and the named-attribute form.
    static GetMapping opCall(string[] value = null, string[] path = null, string[] produces = null)
    {
        GetMapping result;
        result.value = value;
        result.path = path;
        result.produces = produces;
        return result;
    }
}

/// `@PostMapping`.
@RequestMapping(method: [RequestMethod.POST]) struct PostMapping
{
    /// Alias of `RequestMapping.path`.
    @AliasFor(annotation: ClassRef("flint.web.bind.annotation.RequestMapping")) string[] value;
    /// Alias of `RequestMapping.path`.
    @AliasFor(annotation: ClassRef("flint.web.bind.annotation.RequestMapping")) string[] path;

    /// Java's single-value form: `@PostMapping("x")` (aot-contract.md section 2, R2.1).
    static PostMapping opCall(string value, string[] path = null)
    {
        PostMapping result;
        result.value = [value];
        result.path = path;
        return result;
    }

    /// The array form, and the named-attribute form.
    static PostMapping opCall(string[] value = null, string[] path = null)
    {
        PostMapping result;
        result.value = value;
        result.path = path;
        return result;
    }
}

/// `@PathVariable`.
struct PathVariable
{
    /// Alias of `name`.
    @AliasFor("name") string value;
    /// Variable name.
    @AliasFor("value") string name;
    /// Whether the variable is required.
    bool required = true;
}

/// `@RequestParam`.
struct RequestParam
{
    /// Alias of `name`.
    @AliasFor("name") string value;
    /// Parameter name.
    @AliasFor("value") string name;
    /// Whether the parameter is required.
    bool required = true;
    /// Default value.
    string defaultValue = DEFAULT_NONE;
}

/// `@RequestBody`.
struct RequestBody
{
    /// Whether a body is required.
    bool required = true;
}

/// `@ResponseStatus`.
struct ResponseStatus
{
    /// HTTP status code.
    int value;
    /// Reason phrase.
    string reason;
}

/// `@ExceptionHandler`.
struct ExceptionHandler
{
    /// Exception types.
    ClassRef[] value;
}
