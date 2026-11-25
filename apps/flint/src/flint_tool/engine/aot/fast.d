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
Whether the runtime may prove `handler` for the fast path, so the build needs the two beans: one `GET` path, literal
or with whole-segment `{name}` variables; no `params`, `headers` or `consumes`, and `produces` at most exactly
`application/json`; `@ResponseBody` without `@ResponseStatus`; a described plain value, or (S2) a `ResponseEntity`
on a mapping that produces `application/json`; and every parameter an `@RequestParam string` or (S1) a
`@PathVariable` `int`, `long` or `string`, neither validated nor an exception. `@CrossOrigin` is the runtime's to
prove (S3). The runtime decides each endpoint at startup; this only keeps builds that cannot use the fast path from
linking it.
+/
bool fastShape(const ref HandlerPlan handler) pure nothrow
{
    return simpleMapping(handler) && templatePath(handler.paths[0]) && bindableArguments(handler);
}

// One `GET` path, no other condition but `produces = application/json`, `@ResponseBody` without `@ResponseStatus`,
// returning a described plain value or a ResponseEntity with that fixed producible type.
private bool simpleMapping(const ref HandlerPlan handler) pure nothrow
{
    if (handler.paths.length != 1 || handler.params.length || handler.headers.length)
        return false;
    // One GET without consumes, or (S5) one POST consuming exactly application/json.
    const get = handler.methods == ["GET"] && handler.consumes.length == 0;
    const post = handler.methods == ["POST"] && handler.consumes == ["application/json"];
    if (!get && !post)
        return false;
    const json = handler.produces == ["application/json"];
    if (handler.produces.length && !json)
        return false;
    if (!handler.responseBody || handler.status != 0 || handler.reason.length != 0)
        return false;
    const returns = handler.method.returns.name;
    if (returns == "flint.http.ResponseEntity")
        return json;
    return handler.returnDescribed && plainReturn(returns);
}

// A value @ResponseBody writes as it is: not void, and not a type with its own return value handler or status
// (HttpEntity, HttpHeaders, ProblemDetail), nor Object or Any (fast-path.md 3.1).
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

// A path the runtime matches byte for byte: literal segments without pattern syntax, escapes or matrix parameters,
// and whole-segment `{name}` variables.
private bool templatePath(string path) pure nothrow @nogc
{
    if (path.length == 0 || path[0] != '/')
        return false;
    size_t start = 1;
    while (start <= path.length)
    {
        size_t end = start;
        while (end < path.length && path[end] != '/')
            ++end;
        if (!templateSegment(path[start .. end]))
            return false;
        start = end + 1;
    }
    return true;
}

// `{name}` with a word name, or a literal without pattern syntax, escapes or matrix parameters.
private bool templateSegment(string text) pure nothrow @nogc
{
    const variable = text.length > 2 && text[0] == '{' && text[$ - 1] == '}';
    foreach (c; variable ? text[1 .. $ - 1] : text)
        if (variable ? !wordChar(c) : syntaxChar(c))
            return false;
    return true;
}

private bool wordChar(char c) pure nothrow @nogc
{
    return c == '_' || (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

private bool syntaxChar(char c) pure nothrow @nogc
{
    switch (c)
    {
    case '{', '}', '*', '?', '%', ';', '\\':
        return true;
    default:
        return false;
    }
}

// Every parameter an `@RequestParam string` or a `@PathVariable` int, long or string, neither validated nor an
// exception; and (S5) a POST's one `@RequestBody`, validated or not.
private bool bindableArguments(const ref HandlerPlan handler) pure nothrow
{
    size_t bodies;
    foreach (ref argument; handler.arguments)
    {
        if (argument.kind == "requestBody" && !argument.exception)
        {
            ++bodies;
            continue;
        }
        if (argument.validate || argument.exception)
            return false;
        const param = argument.kind == "requestParam" && argument.type == "string";
        const variable = argument.kind == "pathVariable" && (argument.type == "int"
                || argument.type == "long" || argument.type == "string");
        if (!param && !variable)
            return false;
    }
    return handler.methods == ["POST"] ? bodies == 1 : bodies == 0;
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

/// The classes the error-page shortcut's bean needs: Boot's error handling, Jackson auto-configuration (its
/// `stockJsonMapper` proof) and Flint's server factory.
immutable string[] errorShortcutClasses = [
    "flint.boot.webmvc.autoconfigure.error.ErrorPageShortcutCustomizer",
    "flint.boot.jackson.autoconfigure.JacksonAutoConfiguration",
    "flint.boot.web.server.engine.FlintServletWebServerFactory",
];

/++
The error-page shortcut's bean (fast-path.md, "The error-page shortcut"), under the same switch as the fast path: a
`WebServerFactoryCustomizer` that gives the server factory Boot's `StockErrorPageShortcut`, with Boot's Jackson proof.
The shortcut proves the whole ERROR dispatch stock at startup, so the bean does not depend on any endpoint.
+/
BeanPlan errorShortcutBean()
{
    enum customizer = "flint.boot.webmvc.autoconfigure.error.ErrorPageShortcutCustomizer";
    BeanPlan bean;
    bean.name = "flintAotErrorPageShortcut";
    bean.type = customizer;
    bean.types = [customizer, "flint.boot.web.server.WebServerFactoryCustomizer"];
    bean.className = customizer;
    bean.factory = FactoryKind.expression;
    bean.expression = "new " ~ customizer ~ "(&flint.boot.jackson.autoconfigure.stockJsonMapper)";
    bean.expressionModules = [
        "flint.boot.webmvc.autoconfigure.error", "flint.boot.jackson.autoconfigure"
    ];
    bean.source = "Flint AOT: the error-page shortcut";
    return bean;
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
    refuses((ref HandlerPlan h) { h.paths = ["/owners/{id:[0-9]+}"]; });
    refuses((ref HandlerPlan h) { h.paths = ["/files/**"]; });
    refuses((ref HandlerPlan h) { h.paths = ["relative"]; });
    refuses((ref HandlerPlan h) { h.params = ["x=1"]; });
    refuses((ref HandlerPlan h) { h.produces = ["text/plain"]; });
    refuses((ref HandlerPlan h) { h.responseBody = false; });
    refuses((ref HandlerPlan h) { h.status = 201; });
    refuses((ref HandlerPlan h) { h.returnDescribed = false; });
    refuses((ref HandlerPlan h) { h.method.returns.name = "void"; });
    refuses((ref HandlerPlan h) { h.method.returns.name = "flint.http.ResponseEntity"; });
    refuses((ref HandlerPlan h) { h.method.returns.name = "flint.http.ProblemDetail"; });
    refuses((ref HandlerPlan h) { h.arguments[0].type = "int"; });
    refuses((ref HandlerPlan h) { h.arguments[0].kind = "requestBody"; });
    refuses((ref HandlerPlan h) { h.arguments[0].validate = true; });

    // S1-S3: a petclinic-shaped GET by id qualifies.
    HandlerPlan owner = greeting;
    owner.paths = ["/api/owners/{ownerId}"];
    owner.produces = ["application/json"];
    owner.method.returns.name = "flint.http.ResponseEntity";
    owner.returnDescribed = false;
    ArgumentPlan id;
    id.kind = "pathVariable";
    id.name = "ownerId";
    id.type = "int";
    owner.arguments = [id];
    assert(fastShape(owner));

    // S5: a petclinic-shaped validated POST qualifies; without consumes, or with a second body, it does not.
    HandlerPlan add = owner;
    add.paths = ["/api/owners"];
    add.methods = ["POST"];
    add.consumes = ["application/json"];
    ArgumentPlan body;
    body.kind = "requestBody";
    body.name = "ownerFieldsDto";
    body.type = "org.springframework.samples.petclinic.rest.dto.OwnerFieldsDto";
    body.validate = true;
    add.arguments = [body];
    assert(fastShape(add));
    HandlerPlan noConsumes = add;
    noConsumes.consumes = null;
    assert(!fastShape(noConsumes));
    HandlerPlan twoBodies = add;
    twoBodies.arguments = [body, body];
    assert(!fastShape(twoBodies));
}
