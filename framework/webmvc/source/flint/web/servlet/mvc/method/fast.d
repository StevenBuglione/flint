/++
Flint's per-endpoint fast path for `@RequestMapping` handlers (docs/spring/phase1/fast-path.md).

`FastPathTable.build` runs once, when `WebMvcConfigurationSupport` builds the dispatcher strategies. For every
mapping row that carries a Flint AOT `FastInvoker`, it proves against the strategies themselves that the generic
dispatch of a `GET` or `HEAD` to that row's literal path would choose the same handler, bind the same arguments
and write the same response. A row that fails any condition is left out, and its requests keep the generic path.

A served request then costs what the handler costs: the exchange is borrowed from the container, the arguments are
bound straight from the query, content negotiation is a lookup in a table filled at startup by the generic code
itself (`selectMediaType`), and the body is written by the converter's own `ObjectMapper` into a recycled buffer.
Only what user code sees is GC memory: the bound strings and whatever the handler allocates (ADR-030 section 4).
+/
module flint.web.servlet.mvc.method.fast;

import flint.engine.aot.any : Any;
import flint.engine.aot.fast : FastArguments, FastExchange, FastInvoker, FastOutcome;
import flint.engine.aot.mapping : AotHandlerMapping = HandlerMapping;
import flint.http : MediaType;
import flint.http.converter : HttpMessageConverter, HttpMessageNotWritableException;
import flint.http.converter.json : JacksonJsonHttpMessageConverter;
import flint.jakarta.servlet.http : HttpServletRequest, HttpServletResponse;
import flint.util : MimeTypeUtils;
import flint.web.method : HandlerMethod;
import flint.web.method.annotation : RequestParamMethodArgumentResolver;
import flint.web.servlet : DispatcherServlet, FastPath;
import flint.web.servlet.mvc.method : RequestMappingInfo, RequestMappingInfoHandlerMapping;
import flint.web.servlet.mvc.method.annotation : AbstractMessageConverterMethodProcessor,
    RequestMappingHandlerAdapter;

@safe:

/++
The `Accept` values the table answers, compared byte for byte with the request's one `Accept` field; slot 0 is a
request without one. Any other value, or several `Accept` fields, takes the generic path. The set is fixed here, so
the table never grows while requests run.
+/
private immutable string[3] acceptKeys = [null, "*/*", "application/json"];

/// The fast path's routes; `null` from `build` when no row qualifies.
final class FastPathTable : FastPath
{
    private Route[] routes;
    private BodyPool pool;

    private this(Route[] routes)
    {
        this.routes = routes;
        pool = new BodyPool;
    }

    /++
    The routes of `rows` that the strategies prove equal to generic dispatch. `plain` says the strategies around the
    mappings change nothing per request: no interceptors, no CORS configuration source, no custom argument
    resolvers or return value handlers, and the header-only content negotiation manager.
    +/
    static FastPathTable build(const(AotHandlerMapping)[] rows, RequestMappingInfoHandlerMapping mappings,
            RequestMappingHandlerAdapter adapter, bool plain)
    {
        if (!plain)
            return null;
        Route[] routes;
        foreach (ref row; rows)
        {
            if (row.fast is null)
                continue;
            Route route;
            if (prove(row, mappings, adapter, route))
                routes ~= route;
        }
        return routes.length != 0 ? new FastPathTable(routes) : null;
    }

    FastOutcome dispatch(DispatcherServlet servlet, ref scope FastExchange exchange)
    {
        if (exchange.method != "GET" && exchange.method != "HEAD")
            return FastOutcome.declined;
        foreach (ref route; routes)
            if (exchange.path == route.path)
                return serve(route, servlet, exchange);
        return FastOutcome.declined;
    }

    private FastOutcome serve(ref Route route, DispatcherServlet servlet, ref scope FastExchange exchange)
    {
        size_t key;
        if (exchange.acceptCount > 1)
            return FastOutcome.declined;
        if (exchange.acceptCount == 1)
        {
            key = acceptKeys.length;
            foreach (index, candidate; acceptKeys[1 .. $])
                if (exchange.accept == candidate)
                    key = index + 1;
            if (key == acceptKeys.length)
                return FastOutcome.declined;
        }
        const entry = route.accept[key];
        if (entry.contentType is null)
            return FastOutcome.declined; // 406 or a type the table does not write: the generic path answers

        bool requestParamString(string name, string defaultValue, bool required, out string value)
        {
            return bindString(exchange, name, defaultValue, required, value);
        }

        // `scope`, so the delegate borrows this frame instead of a GC closure.
        scope FastArguments arguments;
        arguments.requestParamString = &requestParamString;
        Any result;
        try
        {
            if (!route.invoke(route.bean, arguments, result))
                return FastOutcome.declined;
        }
        catch (Exception ex)
            return complete(servlet, exchange, route, ex, null, null);

        auto buffer = pool.acquire();
        scope (exit)
            pool.release(buffer);
        try
            route.jackson.getMapper().writeValue(&buffer.put, result);
        catch (Exception e)
        {
            // JacksonJsonHttpMessageConverter.writeInternal's wrapping; what it streamed before failing goes out
            // first, as the generic path's response would hold it.
            import flint.java.io : IOException;

            Exception ex = cast(IOException) e !is null ? e
                : new HttpMessageNotWritableException("Could not write JSON: " ~ e.msg, e);
            return complete(servlet, exchange, route, ex, entry.contentType, buffer.data);
        }
        exchange.respond(200, entry.contentType, buffer.data);
        return FastOutcome.written;
    }

    /// The handler ran and `ex` escaped: build the servlet objects and let the dispatcher resolve it.
    private static FastOutcome complete(DispatcherServlet servlet, ref scope FastExchange exchange,
            ref Route route, Exception ex, string contentType, const(ubyte)[] partial)
    {
        Object request, response;
        exchange.materialize(request, response);
        auto servletRequest = cast(HttpServletRequest) request;
        auto servletResponse = cast(HttpServletResponse) response;
        if (partial.length != 0)
        {
            servletResponse.setContentType(contentType);
            servletResponse.getOutputStream().write(partial);
        }
        servlet.completeFastDispatch(servletRequest, servletResponse, route.handler, ex);
        return FastOutcome.materialized;
    }
}

/// One proved endpoint.
private struct Route
{
    string path;
    HandlerMethod handler;
    Object bean;
    FastInvoker invoke;
    JacksonJsonHttpMessageConverter jackson;
    /// Per `acceptKeys` slot: the `Content-Type` the generic path writes, or `null` where it does not write one.
    AcceptEntry[acceptKeys.length] accept;
}

private struct AcceptEntry
{
    string contentType;
}

/++
The mapping proof (fast-path.md): the row is a literal `GET` path without other conditions, `@ResponseBody`,
without `@ResponseStatus`; the generic lookup finds exactly this handler by that path; every parameter goes to the
`@RequestParam` resolver as a `string`; and each `Accept` slot selects a parameterless media type that the Jackson
converter writes. A slot that the generic path answers some other way (406, another converter, a charset) is left
empty, so those requests take the generic path.
+/
private bool prove(ref const AotHandlerMapping row, RequestMappingInfoHandlerMapping mappings,
        RequestMappingHandlerAdapter adapter, out Route route)
{
    if (row.paths.length != 1 || row.methods != ["GET"] || row.params.length || row.headers.length
            || row.consumes.length || row.produces.length || !row.responseBody || row.responseStatus != 0)
        return false;
    const path = row.paths[0];
    if (path.length == 0 || path[0] != '/')
        return false;
    foreach (c; path)
        if (c == '{' || c == '}' || c == '*' || c == '?' || c == '%' || c == ';' || c == '\\')
            return false;
    foreach (ref annotation; row.typeAnnotations)
        if (annotation.type == "flint.web.bind.annotation.CrossOrigin")
            return false;
    if (row.method !is null)
        foreach (ref annotation; row.method.annotations)
            if (annotation.type == "flint.web.bind.annotation.CrossOrigin")
                return false;

    size_t found;
    HandlerMethod handler;
    mappings.visitDirectPath(path, (RequestMappingInfo info, HandlerMethod candidate) {
        ++found;
        handler = candidate;
    });
    if (found != 1 || handler.getFastInvoker() !is row.fast || handler.getResponseStatus() != 0)
        return false;
    foreach (parameter; handler.getMethodParameters())
    {
        auto resolver = adapter.getArgumentResolvers().getArgumentResolver(parameter);
        if (resolver is null || typeid(cast(Object) resolver) !is typeid(RequestParamMethodArgumentResolver)
                || parameter.getParameterType() != "string")
            return false;
    }

    const valueType = row.returnType;
    auto converters = adapter.getMessageConverters();
    auto producible = AbstractMessageConverterMethodProcessor.producibleTypes(converters, valueType);
    if (producible.length == 0)
        return false;
    JacksonJsonHttpMessageConverter jackson;
    foreach (slot, key; acceptKeys)
    {
        MediaType[] acceptable;
        if (key is null)
            acceptable = [MediaType.ALL];
        else
        {
            // HeaderContentNegotiationStrategy.resolveMediaTypes for one Accept field.
            try
                acceptable = MediaType.parseMediaTypes([key]);
            catch (Exception)
                continue;
            MimeTypeUtils.sortBySpecificity(acceptable);
            if (acceptable.length == 0)
                acceptable = [MediaType.ALL];
        }
        MediaType selected;
        if (AbstractMessageConverterMethodProcessor.selectMediaType(acceptable, producible, valueType, selected)
                != AbstractMessageConverterMethodProcessor.Selection.selected)
            continue;
        selected = selected.removeQualityValue();
        // AbstractHttpMessageConverter.addDefaultHeaders keeps a concrete type other than octet-stream as it is.
        if (!selected.isConcrete() || selected.equals(MediaType.APPLICATION_OCTET_STREAM))
            continue;
        HttpMessageConverter writer;
        foreach (converter; converters)
            if (converter.canWrite(valueType, &selected))
            {
                writer = converter;
                break;
            }
        if (writer is null || typeid(cast(Object) writer) !is typeid(JacksonJsonHttpMessageConverter))
            continue;
        const header = selected.toString();
        bool parameterless = true;
        foreach (c; header)
            if (c == ';')
                parameterless = false;
        if (!parameterless)
            continue;
        jackson = cast(JacksonJsonHttpMessageConverter) writer;
        route.accept[slot] = AcceptEntry(header);
    }
    if (jackson is null)
        return false;
    route.path = path;
    route.handler = handler;
    route.bean = handler.getBean();
    route.invoke = row.fast;
    route.jackson = jackson;
    return route.bean !is null;
}

/++
`@RequestParam String` binding as the generic path does it: `RequestParamMethodArgumentResolver.resolveName` reads
every value (then `name[]`), `AbstractNamedValueMethodArgumentResolver` applies the default to an absent or empty
single value, and the conversion service joins several values with `,`. The value is copied to the GC heap in one
allocation, because it reaches user code; a default is the generated literal itself.
+/
private bool bindString(ref scope FastExchange exchange, string name, string defaultValue, bool required,
        out string value)
{
    size_t count, total;
    void measure(scope const(char)[] text)
    {
        ++count;
        total += text.length;
    }

    char[64] arrayName = void;
    const(char)[] lookup = name;
    if (!exchange.parameter(lookup, &measure))
        return false;
    if (count == 0)
    {
        if (name.length + 2 > arrayName.length)
            return false;
        arrayName[0 .. name.length] = name;
        arrayName[name.length .. name.length + 2] = "[]";
        lookup = arrayName[0 .. name.length + 2];
        if (!exchange.parameter(lookup, &measure))
            return false;
    }
    if (count == 0)
    {
        if (defaultValue !is null)
        {
            value = defaultValue;
            return true;
        }
        // A missing required parameter is MissingServletRequestParameterException: the generic path answers it,
        // and the handler has not run.
        return !required;
    }
    if (count == 1 && total == 0)
    {
        value = defaultValue !is null ? defaultValue : "";
        return true;
    }
    char[1024] stack = void;
    const length = total + count - 1;
    if (length > stack.length)
        return false;
    size_t at, seen;
    void copy(scope const(char)[] text)
    {
        if (seen++ != 0)
            stack[at++] = ',';
        stack[at .. at + text.length] = text;
        at += text.length;
    }

    if (!exchange.parameter(lookup, &copy) || at != length)
        return false;
    value = stack[0 .. length].idup;
    return true;
}

/// A recycled body buffer: what the mapper writes before the exchange sends it.
private final class Body
{
    private ubyte[] storage;
    private size_t length;

    this()
    {
        storage = new ubyte[512];
    }

    void put(scope const(ubyte)[] bytes)
    {
        if (length + bytes.length > storage.length)
        {
            size_t capacity = storage.length * 2;
            while (capacity < length + bytes.length)
                capacity *= 2;
            auto grown = new ubyte[capacity];
            grown[0 .. length] = storage[0 .. length];
            storage = grown;
        }
        storage[length .. length + bytes.length] = bytes;
        length += bytes.length;
    }

    const(ubyte)[] data() const return
    {
        return storage[0 .. length];
    }
}

/++
Body buffers shared by the reactor threads: slots taken and returned with compare-and-swap, as `JsonFactory`
recycles its generators, since framework packages keep no thread-local state. A buffer that grew past 64 KiB is
dropped rather than kept.
+/
private final class BodyPool
{
    private Body[16] slots;

    Body acquire()
    {
        import core.atomic : atomicLoad, cas;

        foreach (ref slot; slots)
        {
            auto buffer = atomicLoad(slot);
            if (buffer !is null && cas(&slot, buffer, cast(Body) null))
            {
                buffer.length = 0;
                return buffer;
            }
        }
        return new Body;
    }

    void release(Body buffer)
    {
        import core.atomic : atomicLoad, cas;

        if (buffer.storage.length > 64 * 1024)
            return;
        foreach (ref slot; slots)
            if (atomicLoad(slot) is null && cas(&slot, cast(Body) null, buffer))
                return;
    }
}
