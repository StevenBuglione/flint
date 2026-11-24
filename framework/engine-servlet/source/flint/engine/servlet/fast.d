/++
The container's side of the per-endpoint fast path (docs/spring/phase1/fast-path.md).

Before it builds the servlet request, the engine offers the exchange to a servlet that implements `FastDispatch`.
The exchange is built on the fiber's stack from the arena: the path, query and first `Accept` value are copied
into a fixed stack buffer, and a request whose head does not fit is never offered. Query parameters decode with
the servlet request's own decoder (`decodeComponentInto`), into stack storage. Nothing here allocates on the GC
heap; only a value the dispatcher hands to user code is copied out, by the dispatcher.

The servlet request and response are built only when the dispatcher asks (`materialize`), through the same
`capture` the generic path uses, so an exception after the handler ran reaches the resolvers and the error page
with the objects it would have had.
+/
module flint.engine.servlet.fast;

import flint.arena : Buffer;
import flint.conc : Context;
import flint.engine.aot.fast : FastDispatch, FastExchange, FastField, FastFilterEffect, FastOutcome, FastValueVisitor;
import flint.engine.servlet : ServletEngine;
import flint.engine.servlet.request : ServletEngineRequest, componentTooLong, decodeComponent,
    decodeComponentInto, malformedComponent, methodName;
import flint.engine.servlet.response : ServletEngineResponse, defaultBufferSize;
import flint.engine.web.fiber : FiberResponse, unknownLength;
import flint.engine.web.stream : StreamField;
import flint.engine.web.types : Method, Request, RequestContext;

@safe:

/// The request head the fast path copies to the stack; a larger one is served generically.
private enum size_t headLimit = 2048;

/// The longest parameter name or value the fast path decodes; a longer one makes it decline.
private enum size_t valueLimit = 1024;

/++
Offer one exchange to `dispatch`. `declined`: nothing ran and nothing was sent. `written`: the response is complete.
`materialized`: `servletRequest` and `servletResponse` are set, and `failure` holds what escaped the dispatcher, if
anything; the caller finishes them as it finishes the generic path. This is `ServletEngineOptions.fastOffer`, which
only Flint AOT's generated customizer sets; it is public for that customizer alone.
+/
FastOutcome serveFast(ServletEngine engine, FastDispatch dispatch, ref scope Request request,
        ref scope RequestContext context, FiberResponse transport,
        out ServletEngineRequest servletRequest, out ServletEngineResponse servletResponse, out Exception failure)
{
    const method = request.method();
    if (method != Method.get && method != Method.head)
        return FastOutcome.declined;
    char[headLimit] head = void;
    size_t used;
    bool fits = true;
    // Copies one arena buffer behind what is already in `head`; the slice is valid for this call only.
    const(char)[] take(Buffer buffer)
    {
        size_t start = used, end = used;
        auto room = head[used .. $];
        bool ok = true;
        context.arena.read(buffer, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
            if (bytes.length > room.length)
            {
                ok = false;
                return;
            }
            room[0 .. bytes.length] = cast(const(char)[]) bytes;
            end = start + bytes.length;
        });
        if (!ok)
        {
            fits = false;
            return null;
        }
        used = end;
        return head[start .. end];
    }

    const pathBuffer = request.path();
    if (!pathBuffer.ok())
        return FastOutcome.declined;
    auto path = take(pathBuffer.value);
    const queryBuffer = request.query();
    const(char)[] query = queryBuffer.ok() ? take(queryBuffer.value) : null;
    // `scope`, so the delegates below borrow this frame instead of a GC closure (DMD and LDC; -vgc shows none).
    scope FastExchange exchange;
    // The first `Accept` field and the number of them, in one pass over the fields.
    Buffer acceptField;
    exchange.acceptCount = request.firstHeader("accept", acceptField);
    if (exchange.acceptCount != 0)
        exchange.accept = take(acceptField);
    Buffer originField;
    exchange.originCount = request.firstHeader("origin", originField);
    if (!fits)
        return FastOutcome.declined;
    const contextPath = engine.contextPathOf();
    if (contextPath.length != 0)
    {
        // Tomcat maps `/ctx` itself and `/ctx/...`; anything else is the host's 404, which the generic path sends.
        if (path.length <= contextPath.length || path[0 .. contextPath.length] != contextPath
                || path[contextPath.length] != '/')
            return FastOutcome.declined;
        path = path[contextPath.length .. $];
    }
    exchange.method = methodName(method);
    exchange.path = path;
    exchange.filterFields = engine.fastFilterFields;

    bool parameter(scope const(char)[] name, scope FastValueVisitor visit)
    {
        return visitParameter(query, name, visit);
    }

    bool began;
    void respond(int status, string contentType, scope const(ubyte)[] content)
    {
        Context transportContext;
        StreamField[1] storage = [StreamField("Content-Type", contentType)];
        const fields = contentType is null ? storage[0 .. 0] : storage[];
        began = true;
        // As the servlet response frames the same bytes written without a flush: buffered up to its buffer size
        // and sent with Content-Length, else committed when the buffer overflows and sent chunked.
        if (content.length <= defaultBufferSize)
        {
            check(transport.respond(cast(ushort) status, fields, content, false, transportContext));
            return;
        }
        check(transport.begin(cast(ushort) status, fields, unknownLength, transportContext));
        check(transport.send(content, transportContext));
        check(transport.finish(transportContext));
    }

    void respondFields(int status, scope const(FastField)[] given, scope const(ubyte)[] content, bool chunked)
    {
        Context transportContext;
        StreamField[16] storage;
        auto fields = streamFields(given, storage);
        began = true;
        if (!chunked && content.length <= defaultBufferSize)
        {
            check(transport.respond(cast(ushort) status, fields, content, false, transportContext));
            return;
        }
        check(transport.begin(cast(ushort) status, fields, unknownLength, transportContext));
        if (content.length != 0)
            check(transport.send(content, transportContext));
        check(transport.finish(transportContext));
    }

    void materialize(out Object materializedRequest, out Object materializedResponse)
    {
        if (servletRequest is null)
        {
            servletRequest = engine.captureRequest(request, context);
            servletResponse = engine.newResponse(transport);
            // What the mapped filters wrote before the servlet ran (HeaderWriterFilter writes eagerly), on the
            // fresh response, where their writers' presence checks all pass.
            foreach (ref field; engine.fastFilterFields)
                servletResponse.addHeader(field.name, field.value);
        }
        materializedRequest = servletRequest;
        materializedResponse = servletResponse;
    }

    exchange.parameter = &parameter;
    exchange.respond = &respond;
    exchange.respondFields = &respondFields;
    exchange.materialize = &materialize;
    // The filters' per-request state (a security context) around the servlet, undone in reverse order on every
    // path, for exactly the filters whose enter ran (one that throws is not undone, as its filter never ran).
    size_t entered;
    scope (exit)
        exitFilters(engine, entered);
    enterFilters(engine, entered);
    FastOutcome outcome;
    try
        outcome = dispatch.dispatchFast(exchange);
    catch (Exception e)
    {
        // Once the response is on the wire (the client went away mid-body), the generic path's committed response
        // would forward nowhere: the exception leaves the exchange as complete()'s IOException does (web-http).
        if (began)
            throw e;
        // A filter that answers such an exception itself (ExceptionTranslationFilter's security exceptions) does so
        // on the servlet objects, innermost first, as the exception would have passed the filters.
        if (auto effect = filterHandling(engine, e))
        {
            Object handledRequest, handledResponse;
            materialize(handledRequest, handledResponse);
            effect.handle(handledRequest, handledResponse, e);
            return FastOutcome.materialized;
        }
        // Whatever escapes the dispatcher is an uncaught exception of the generic path: the container answers it
        // with its servlet objects, built now if the dispatcher had not.
        failure = e;
        Object ignoredRequest, ignoredResponse;
        materialize(ignoredRequest, ignoredResponse);
        return FastOutcome.materialized;
    }
    if (outcome == FastOutcome.materialized && servletRequest is null)
    {
        Object ignoredRequest, ignoredResponse;
        materialize(ignoredRequest, ignoredResponse);
    }
    return outcome;
}

/// The fields as the transport takes them, on `storage` when they fit; more is a GC copy, as the handler ran.
private StreamField[] streamFields(scope const(FastField)[] given, return ref StreamField[16] storage)
{
    StreamField[] fields = given.length <= storage.length ? storage[0 .. given.length] : new StreamField[given.length];
    foreach (index, ref field; given)
        fields[index] = StreamField(field.name, field.value);
    return fields;
}

/// Runs each mapped filter's `enter` in chain order; `entered` counts those that ran.
private void enterFilters(ServletEngine engine, ref size_t entered)
{
    foreach (ref effect; engine.fastFilterEffects)
    {
        if (effect.enter !is null)
            effect.enter();
        ++entered;
    }
}

/// Undoes the first `entered` filters' `enter`, innermost first.
private void exitFilters(ServletEngine engine, size_t entered)
{
    foreach_reverse (ref effect; engine.fastFilterEffects[0 .. entered])
        if (effect.exit !is null)
            effect.exit();
}

/// The innermost mapped filter that answers `e` itself, or null.
private FastFilterEffect* filterHandling(ServletEngine engine, Exception e)
{
    foreach_reverse (ref effect; engine.fastFilterEffects)
        if (effect.handles !is null && effect.handles(e))
            return &effect;
    return null;
}

/++
Every value of query parameter `name`, as `ServletEngineRequest.getParameterValues` returns them: pairs split on
`&`, empty pairs and pairs whose name or value is malformed percent-encoding skipped (Tomcat), `+` a space.
`false` when a name or value is longer than the fast path decodes.
+/
package(flint.engine.servlet) bool visitParameter(scope const(char)[] query, scope const(char)[] name,
        scope FastValueVisitor visit)
{
    char[valueLimit] nameStorage = void;
    char[valueLimit] valueStorage = void;
    size_t start;
    while (start <= query.length)
    {
        size_t end = start;
        while (end < query.length && query[end] != '&')
            ++end;
        const pair = query[start .. end];
        start = end + 1;
        if (pair.length == 0)
            continue;
        size_t equals = pair.length;
        foreach (index, c; pair)
        {
            if (c == '=')
            {
                equals = index;
                break;
            }
        }
        const decodedName = decodeComponentInto(pair[0 .. equals], nameStorage[]);
        if (decodedName == componentTooLong)
            return false;
        if (decodedName <= 0) // malformed or empty: skipped, as Tomcat skips it
            continue;
        if (nameStorage[0 .. decodedName] != name)
            continue;
        if (equals == pair.length)
        {
            visit("");
            continue;
        }
        const decodedValue = decodeComponentInto(pair[equals + 1 .. $], valueStorage[]);
        if (decodedValue == componentTooLong)
            return false;
        if (decodedValue == malformedComponent)
            continue;
        visit(valueStorage[0 .. decodedValue]);
    }
    return true;
}

private void check(E)(E result)
{
    import flint.arena : Status;
    import flint.java.io : IOException;

    if (result.code != Status.ok)
        throw new IOException("the client connection is no longer writable: " ~ result.message);
}

@("decodeComponentInto and decodeComponent agree, malformed and empty input included")
unittest
{
    static immutable string[] corpus = [
        "", "plain", "a+b", "%41", "%4", "%", "%%", "%zz", "%4g", "x%41y", "%C3%A9t%C3%A9",
        "Jane+Q%20Public", "%22quoted%22%5Cslash%3C%3E", "a%2", "a%2B", "+", "++%2b", "%ff%FE",
        "%0a%0D", "name[]", "n%61me", "%e9", "trailing%", "trailing%4", "%41%", "%41%4", "%41%41",
    ];
    char[valueLimit] storage;
    foreach (text; corpus)
    {
        const expected = decodeComponent(text);
        const got = decodeComponentInto(text, storage[]);
        if (expected is null)
            assert(got == malformedComponent, text);
        else
        {
            assert(got >= 0, text);
            assert(storage[0 .. got] == expected, text);
        }
    }
    char[2] small;
    assert(decodeComponentInto("abc", small[]) == componentTooLong);
}

@("visitParameter yields getParameterValues' values: repeats in order, malformed pairs skipped, encoded names")
unittest
{
    string[] values;
    void collect(scope const(char)[] value) @safe
    {
        values ~= value.idup;
    }

    assert(visitParameter("name=a&name=b", "name", &collect));
    assert(values == ["a", "b"]);
    values = null;
    assert(visitParameter("n%61me=x&other=1&name=%zz&name&&name=", "name", &collect));
    assert(values == ["x", "", ""]);
    values = null;
    assert(visitParameter("name=Jane+Q%20Public", "name", &collect));
    assert(values == ["Jane Q Public"]);
    values = null;
    assert(visitParameter("%zz=1&name[]=v", "name", &collect));
    assert(values.length == 0);
    assert(visitParameter("%zz=1&name[]=v", "name[]", &collect));
    assert(values == ["v"]);
    values = null;
    assert(visitParameter(null, "name", &collect));
    assert(values.length == 0);
    char[valueLimit + 1] huge = 'a';
    assert(!visitParameter("name=" ~ huge.idup, "name", &collect));
}
