/++
Flint AOT's per-endpoint fast path (docs/spring/phase1/fast-path.md): for a request mapping of a provably simple
shape, a `fast_<id>` function that binds the handler's arguments straight from the borrowed exchange and calls the
handler, with no `HandlerArguments`, `Any[]` or resolver in between.

Emitted only when the build asks for it (`AotRequest.fastPath`); a mapping of any other shape gets nothing, not a
diagnostic, and keeps the generic path. The runtime (`flint.web.servlet.mvc.method.fast`) proves the rest at startup
against the configured strategies.
+/
module flint_tool.engine.aot.fast;

import flint_tool.engine.aot.plan : HandlerPlan;

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
    return handler.returnDescribed && handler.method.returns.name != "void";
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

/// The `fast_<id>` function for `handler`, which `fastShape` accepted.
string fastHandler(const ref HandlerPlan handler, string id)
{
    import std.conv : to;
    import flint_tool.engine.aot.conditions : literal;

    string text = "private bool fast_" ~ id ~ "(Object bean, ref scope FastArguments arguments, ref Any result)\n{\n";
    string call;
    foreach (index, ref argument; handler.arguments)
    {
        const name = "a" ~ index.to!string;
        text ~= "    string " ~ name ~ ";\n    if (!arguments.requestParamString(" ~ literal(
                argument.name) ~ ", " ~ (argument.hasDefault
                ? literal(argument.defaultValue) : "null") ~ ", " ~ (argument.required
                ? "true" : "false") ~ ", " ~ name ~ "))\n        return false;\n";
        call ~= (index ? ", " : "") ~ name;
    }
    return text ~ "    result = Any.of((cast(" ~ handler.className ~ ") bean)." ~ handler.method.name
        ~ "(" ~ call ~ "));\n    return true;\n}\n\n";
}

@("fastShape accepts gs-rest-service's greeting and refuses every other shape; fastHandler binds by literal")
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
    const text = fastHandler(greeting, "id");
    assert(text == "private bool fast_id(Object bean, ref scope FastArguments arguments, ref Any result)\n{\n"
            ~ "    string a0;\n    if (!arguments.requestParamString(\"name\", \"World\", false, a0))\n"
            ~ "        return false;\n    result = Any.of((cast(com.example.restservice.GreetingController) bean)"
            ~ ".greeting(a0));\n    return true;\n}\n\n", text);

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
    refuses((ref HandlerPlan h) { h.arguments[0].kind = "pathVariable"; });
    refuses((ref HandlerPlan h) { h.arguments[0].type = "int"; });
    refuses((ref HandlerPlan h) { h.arguments[0].validate = true; });
}
