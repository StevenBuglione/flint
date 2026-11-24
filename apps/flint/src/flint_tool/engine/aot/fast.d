/++
Flint AOT's per-endpoint fast path (docs/spring/phase1/fast-path.md). The fast path is table-driven: the runtime
(`flint.web.servlet.mvc.method.fast`) binds a qualifying mapping's arguments from its `ArgumentSpec`s into stack
storage and calls the mapping's existing array invoker (contract 4), so no endpoint gets generated code of its own
(playbook B-3; the coordinator's size rule for petclinic-rest). What Flint AOT adds is the two pay-for-use beans,
when the build asks for the fast path (`AotRequest.fastPath`) and at least one mapping has a shape the runtime can
prove; the runtime proves each mapping at startup against the configured strategies.
+/
module flint_tool.engine.aot.fast;

import flint_tool.engine.aot.plan : BeanPlan, FactoryKind, HandlerPlan, Plan;

@safe:

/++
Whether Flint AOT may specialise `handler`: one literal `GET` path; no `params`, `headers`, `consumes` or `produces`;
`@ResponseBody` without `@ResponseStatus`; a non-void, described return type (the Jackson converter writes it by
its descriptor); and every parameter an `@RequestParam string`, neither validated nor an exception.
+/
bool fastShape(const ref HandlerPlan handler) pure nothrow
{
    return simpleMapping(handler) && literalPath(handler.paths[0]) && requestParamsOnly(handler);
}

// One `GET` path, no other condition, `@ResponseBody` of a described non-void type, no `@ResponseStatus`.
private bool simpleMapping(const ref HandlerPlan handler) pure nothrow
{
    if (handler.paths.length != 1 || handler.methods != ["GET"])
        return false;
    if (handler.params.length || handler.headers.length || handler.consumes.length || handler.produces.length)
        return false;
    if (!handler.responseBody || handler.status != 0 || handler.reason.length != 0)
        return false;
    return !crossOrigin(handler) && handler.returnDescribed && plainReturn(handler.method.returns.name);
}

// `@CrossOrigin` on the class (merged) or the method: CORS processing adds Vary fields (fast-path.md 4).
private bool crossOrigin(const ref HandlerPlan handler) pure nothrow
{
    enum name = "flint.web.bind.annotation.CrossOrigin";
    foreach (ref item; handler.typeAnnotations.items)
        if (item.annotation.type == name)
            return true;
    foreach (ref annotation; handler.method.annotations)
        if (annotation.type == name)
            return true;
    return false;
}

// A value @ResponseBody writes as it is: not void, and not a type with its own return value handler or status
// (ResponseEntity, HttpEntity, HttpHeaders, ProblemDetail), nor Object or Any (fast-path.md 3.1).
private bool plainReturn(string type) pure nothrow @nogc
{
    switch (type)
    {
    case "void", "object.Object", "flint.engine.aot.any.Any", "flint.http.ResponseEntity",
            "flint.http.HttpEntity", "flint.http.HttpHeaders", "flint.http.ProblemDetail":
            return false;
    default:
        return true;
    }
}

// A path the request's raw bytes can be compared with: no pattern syntax, no escapes, no matrix parameters.
private bool literalPath(string path) pure nothrow @nogc
{
    if (path.length == 0 || path[0] != '/')
        return false;
    foreach (c; path)
        if (c == '{' || c == '}' || c == '*' || c == '?' || c == '%' || c == ';' || c == '\\')
            return false;
    return true;
}

// Every parameter an `@RequestParam string`, neither validated nor an exception.
private bool requestParamsOnly(const ref HandlerPlan handler) pure nothrow
{
    foreach (ref argument; handler.arguments)
        if (argument.kind != "requestParam" || argument.type != "string" || argument.validate || argument.exception)
            return false;
    return true;
}

/// The classes the fast path's beans need, probed for presence like the date customizer's.
immutable string[] fastPathClasses = [
    "flint.web.servlet.mvc.method.fast.FastPathConfigurer",
    "flint.boot.web.server.WebServerFactoryCustomizer",
    "flint.boot.web.server.engine.FlintServletWebServerFactory",
];

/// Whether the plan holds at least one handler `fastShape` accepts.
bool hasFastHandler(const ref Plan plan) pure nothrow
{
    foreach (ref item; plan.modules)
        foreach (ref handler; item.handlers)
            if (fastShape(handler))
                return true;
    return false;
}

/++
The two beans that make the fast path pay-for-use (fast-path.md, section 9): a `WebMvcConfigurer` that gives
`WebMvcConfigurationSupport` its table, and a `WebServerFactoryCustomizer` that gives the servlet engine its offer.
Nothing else references the table or the offer, so a build without these beans links neither.
+/
BeanPlan[] fastPathBeans()
{
    enum configurer = "flint.web.servlet.mvc.method.fast.FastPathConfigurer";
    enum customizer = "flint.boot.web.server.WebServerFactoryCustomizer";
    enum factory = "flint.boot.web.server.engine.FlintServletWebServerFactory";
    BeanPlan table;
    table.name = "flintAotFastPathConfigurer";
    table.type = configurer;
    table.types = [configurer, "flint.web.servlet.config.annotation.WebMvcConfigurer"];
    table.className = configurer;
    table.factory = FactoryKind.expression;
    table.expression = "new " ~ configurer ~ "()";
    table.expressionModules = ["flint.web.servlet.mvc.method.fast"];
    table.source = "Flint AOT: an endpoint qualifies for the fast path";
    BeanPlan offer;
    offer.name = "flintAotFastPathOffer";
    offer.type = customizer;
    offer.types = [customizer];
    offer.className = customizer;
    offer.factory = FactoryKind.expression;
    offer.expression = "new class " ~ customizer ~ " {\n        void customize("
        ~ "flint.boot.web.server.servlet.ConfigurableServletWebServerFactory factory) @safe\n        {\n"
        ~ "            if (auto server = cast(" ~ factory ~ ") factory)\n"
        ~ "                server.setFastOffer(&flint.engine.servlet.fast.serveFast);\n        }\n    }";
    offer.expressionModules = [
        "flint.boot.web.server", "flint.boot.web.server.engine", "flint.boot.web.server.servlet",
        "flint.engine.servlet.fast"
    ];
    offer.source = table.source;
    return [table, offer];
}

@("fastShape accepts gs-rest-service's greeting and refuses every other shape")
unittest
{
    import flint_tool.engine.aot.plan : ArgumentPlan;

    HandlerPlan greeting;
    greeting.className = "com.example.restservice.GreetingController";
    greeting.method.name = "greeting";
    greeting.method.returns.name = "com.example.restservice.Greeting";
    greeting.paths = ["/greeting"];
    greeting.methods = ["GET"];
    greeting.responseBody = true;
    greeting.returnDescribed = true;
    ArgumentPlan name;
    name.kind = "requestParam";
    name.name = "name";
    name.type = "string";
    name.hasDefault = true;
    name.defaultValue = "World";
    greeting.arguments = [name];
    assert(fastShape(greeting));

    void refuses(void delegate(ref HandlerPlan) @safe change)
    {
        auto copy = greeting;
        copy.arguments = greeting.arguments.dup;
        change(copy);
        assert(!fastShape(copy));
    }

    refuses((ref HandlerPlan h) { h.methods = ["POST"]; });
    refuses((ref HandlerPlan h) { h.methods = ["GET", "HEAD"]; });
    refuses((ref HandlerPlan h) { h.paths = ["/a", "/b"]; });
    refuses((ref HandlerPlan h) { h.paths = ["/owners/{id}"]; });
    refuses((ref HandlerPlan h) { h.paths = ["/files/**"]; });
    refuses((ref HandlerPlan h) { h.paths = ["relative"]; });
    refuses((ref HandlerPlan h) { h.params = ["x=1"]; });
    refuses((ref HandlerPlan h) { h.produces = ["application/json"]; });
    refuses((ref HandlerPlan h) { h.responseBody = false; });
    refuses((ref HandlerPlan h) { h.status = 201; });
    refuses((ref HandlerPlan h) { h.returnDescribed = false; });
    refuses((ref HandlerPlan h) { h.method.returns.name = "void"; });
    refuses((ref HandlerPlan h) { h.method.returns.name = "flint.http.ResponseEntity"; });
    refuses((ref HandlerPlan h) { h.method.returns.name = "flint.http.ProblemDetail"; });
    refuses((ref HandlerPlan h) { h.arguments[0].kind = "pathVariable"; });
    refuses((ref HandlerPlan h) { h.arguments[0].type = "int"; });
    refuses((ref HandlerPlan h) { h.arguments[0].validate = true; });
}
