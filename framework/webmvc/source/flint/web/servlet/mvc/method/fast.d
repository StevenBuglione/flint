/++
Flint's per-endpoint fast path for `@RequestMapping` handlers (docs/spring/phase1/fast-path.md).

`FastPathTable.build` runs once, when `WebMvcConfigurationSupport` builds the dispatcher strategies. For every
mapping row with Flint AOT's array invoker (contract 4), it proves against the strategies themselves that the generic
dispatch of a `GET` or `HEAD` to that row's literal path would choose the same handler, bind the same arguments
and write the same response. A row that fails any condition is left out, and its requests keep the generic path.

The fast path is table-driven (playbook B-3): it binds each argument from the row's `ArgumentSpec` into stack
storage and calls the row's existing array invoker, so no endpoint carries generated code of its own. A served
request then costs what the handler costs: the exchange is borrowed from the container, the arguments are bound
straight from the query, content negotiation is a lookup in a table filled at startup by the generic code
itself (`selectMediaType`), and the body is written by the converter's own `ObjectMapper` into a recycled buffer.
Only what user code sees is GC memory: the bound strings and whatever the handler allocates (ADR-030 section 4).
+/
module flint.web.servlet.mvc.method.fast;

import flint.engine.aot.any : Any;
import flint.engine.aot.fast : FastExchange, FastField, FastOutcome;
import flint.engine.aot.mapping : AotHandlerMapping = HandlerMapping, ArgumentKind, ArgumentSpec;
import flint.http : HttpHeaders, MediaType, ResponseEntity;
import flint.http.converter : HttpMessageConverter, HttpMessageNotWritableException;
import flint.http.converter.json : JacksonJsonHttpMessageConverter;
import flint.jakarta.servlet.http : HeaderFieldSource, HttpServletRequest, HttpServletResponse;
import flint.util : MimeTypeUtils;
import flint.web.context.request : ServletWebRequest;
import flint.web.accept : HeaderContentNegotiationStrategy;
import flint.web.cors : DefaultCorsProcessor;
import flint.web.method : HandlerMethod;
import flint.web.method.support : ModelAndViewContainer;
import flint.web.bind.annotation : ValueConstants;
import flint.web.method.annotation : RequestParamMethodArgumentResolver;
import flint.web.servlet : DispatcherStrategies, DispatcherServlet, FastPath, FastPathFactory;
import flint.web.servlet.config.annotation : WebMvcConfigurer;
import flint.web.servlet.mvc.method : RequestMappingInfo, RequestMappingInfoHandlerMapping;
import flint.web.servlet.mvc.method.annotation : AbstractMessageConverterMethodProcessor,
    HttpEntityMethodProcessor, HttpHeadersReturnValueHandler,
    PathVariableMethodArgumentResolver,
    RequestMappingHandlerAdapter, RequestMappingHandlerMapping,
    RequestResponseBodyMethodProcessor, ServletRequestMethodArgumentResolver;
import flint.core : MethodParameter;

@safe:

/++
The `Accept` values the table answers, compared byte for byte with the request's one `Accept` field; slot 0 is a
request without one. Any other value, or several `Accept` fields, takes the generic path. The set is fixed here, so
the table never grows while requests run.
+/
private immutable string[3] acceptKeys = [null, "*/*", "application/json"];

/++
The `WebMvcConfigurer` bean Flint AOT generates (`flintAotFastPathConfigurer`) when an endpoint qualifies: it is the
only path to `FastPathTable`, so an application without it links none of the fast path (fast-path.md, section 9).
+/
final class FastPathConfigurer : WebMvcConfigurer, FastPathFactory
{
    FastPath buildFastPath(ref DispatcherStrategies strategies, const(AotHandlerMapping)[] rows, bool plain)
    {
        // The proof reads the mapping and adapter WebMvcConfigurationSupport put first (fast-path.md 3.2).
        if (strategies.handlerMappings.length == 0 || strategies.handlerAdapters.length == 0)
            return null;
        auto mappings = cast(RequestMappingInfoHandlerMapping) strategies.handlerMappings[0];
        auto adapter = cast(RequestMappingHandlerAdapter) strategies.handlerAdapters[0];
        if (mappings is null || adapter is null)
            return null;
        return FastPathTable.build(rows, mappings, adapter, plain);
    }
}

/// The fast path's routes; `null` from `build` when no row qualifies.
final class FastPathTable : FastPath
{
    private Route[] routes;
    private BodyPool pool;
    // S6: the first handler mapping, when it is exactly Spring's RequestMappingHandlerMapping (a subclass could look
    // up otherwise); null keeps every unmatched request generic.
    private RequestMappingInfoHandlerMapping unmatched;
    // Full S6: the literal text every registration pattern of `unmatched` starts with, up to its first variable or
    // wildcard. A path that starts with none of them is matched by none of the patterns.
    private string[] patternPrefixes;

    private this(Route[] routes, RequestMappingInfoHandlerMapping mappings)
    {
        this.routes = routes;
        pool = new BodyPool;
        if (typeid(mappings) is typeid(RequestMappingHandlerMapping))
        {
            unmatched = mappings;
            foreach (info; mappings.registeredMappingInfos())
                foreach (pattern; info.getPatterns())
                    patternPrefixes ~= literalPrefix(pattern.getPatternString());
        }
    }

    /++
    The routes of `rows` that the strategies prove equal to generic dispatch. `plain` says the strategies around the
    mappings change nothing per request: no interceptors, no CORS configuration source, no custom argument
    resolvers or return value handlers, and the header-only content negotiation manager.
    +/
    static FastPathTable build(const(AotHandlerMapping)[] rows,
            RequestMappingInfoHandlerMapping mappings, RequestMappingHandlerAdapter adapter, bool plain)
    {
        if (!plain)
            return null;
        // Literal routes first: lookupHandlerMethod prefers a direct path match to any pattern, and a template
        // route proves only that no other GET mapping overlaps the values it binds.
        Route[] literal, templates;
        foreach (ref row; rows)
        {
            if (row.invokeArguments is null)
                continue;
            Route route;
            if (prove(row, mappings, adapter, route))
            {
                if (route.segments.length == 0)
                    literal ~= route;
                else
                    templates ~= route;
            }
        }
        auto proved = literal ~ templates;
        return proved.length != 0 ? new FastPathTable(proved, mappings) : null;
    }

    FastOutcome dispatch(DispatcherServlet servlet, ref scope FastExchange exchange)
    {
        foreach (ref route; routes)
        {
            if (!answers(route, exchange.method))
                continue;
            Span[maxArguments] values;
            if (route.segments.length == 0 ? exchange.path == route.path : matchTemplate(exchange.path,
                    route.segments, values))
                return serve(route, servlet, exchange, values);
        }
        // S6: a GET no route took goes straight to doDispatch on the servlet objects (fast-path.md 9.1.2), or, when
        // no registration can match its path, to the container's proved error page without them (9.1.3).
        if (unmatched !is null && exchange.method == "GET" && typeid(servlet) is typeid(DispatcherServlet))
        {
            if (exchange.unmatched !is null && plainPath(exchange.path)
                    && !anyPrefix(exchange.path) && exchange.unmatched())
                return FastOutcome.written;
            return serveUnmatched(servlet, exchange);
        }
        return FastOutcome.declined;
    }

    // Whether `path` starts with a registration pattern's literal prefix, ignoring ASCII case (a pattern parser
    // may match case-insensitively; a false positive only keeps the request on the servlet objects).
    private bool anyPrefix(scope const(char)[] path) const
    {
        foreach (prefix; patternPrefixes)
            if (path.length >= prefix.length && equalsAsciiIgnoreCase(path[0 .. prefix.length], prefix))
                return true;
        return false;
    }

    /++
    S6: the generic dispatch of a `GET` that no route took, entered at `doDispatch` (`doGet`, `processRequest` and
    `doService` only lead there). When no registration of the first handler mapping has a pattern that matches the
    path (the lookup's own `PathPattern.matches` on the request's own parse), that mapping's lookup would find
    nothing, so the dispatch skips it: an unmatched request, typically a 404, costs no lookup. Otherwise it is
    `doDispatch` itself. Either way the response is the generic one.
    +/
    private FastOutcome serveUnmatched(DispatcherServlet servlet, ref scope FastExchange exchange)
    {
        Object request, response;
        exchange.materialize(request, response);
        auto servletRequest = cast(HttpServletRequest) request;
        auto servletResponse = cast(HttpServletResponse) response;
        servlet.dispatchUnmatched(servletRequest, servletResponse, firstMappingMisses(servletRequest));
        return FastOutcome.materialized;
    }

    // Whether no pattern of any registration of the first mapping matches the request's lookup path.
    private bool firstMappingMisses(HttpServletRequest request)
    {
        import flint.web.servlet.handler : parsedLookupPath;

        const path = parsedLookupPath(request);
        foreach (info; unmatched.registeredMappingInfos())
            foreach (pattern; info.getPatterns())
                if (pattern.matches(path))
                    return false;
        return true;
    }

    private FastOutcome serve(ref Route route, DispatcherServlet servlet,
            ref scope FastExchange exchange, ref const Span[maxArguments] values)
    {
        size_t key;
        if (!admitted(route, exchange, key))
            return FastOutcome.declined;
        const entry = route.accept[key];
        // Every argument is bound before the handler runs, so a declined request has run nothing. S5: a body that
        // RequestResponseBodyMethodProcessor's own validation rejects is resolved as doDispatch resolves it (the
        // handler has not run).
        Any[maxArguments] arguments;
        Exception failure;
        if (!bound(route, exchange, values, arguments, failure))
            return FastOutcome.declined;
        if (failure !is null)
            return complete(servlet, exchange, route, failure, 0, null, null);
        Any result;
        try
            result = route.handler.invokeArguments(arguments[0 .. route.arguments.length], null);
        catch (Exception ex)
            return complete(servlet, exchange, route, ex, 0, null, null);
        if (route.entityProcessor !is null)
            return serveEntity(route, servlet, exchange, result, key);

        // writeWithMessageConverters writes no body and no Content-Type for a null value: a 200 with Content-Length 0.
        FastField[maxFields] storage;
        if (result.isNull())
        {
            exchange.respondFields(200, responseFields(route, exchange, null, storage), null, false);
            return FastOutcome.written;
        }
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

            Exception ex = cast(IOException) e !is null ? e : new HttpMessageNotWritableException(
                    "Could not write JSON: " ~ e.msg, e);
            return complete(servlet, exchange, route, ex, 0, entry.contentType, buffer.data);
        }
        exchange.respondFields(200, responseFields(route, exchange, entry.contentType, storage), buffer.data, false);
        return FastOutcome.written;
    }

    // The guards that decline before anything runs: the Accept key; S3's Origin on a route with a CORS
    // configuration (DefaultCorsProcessor answers it generically); a key the table does not write (406, or a type the
    // generic path chooses); S5's body offered whole as the proved Content-Type.
    private static bool admitted(ref const Route route, ref scope FastExchange exchange, out size_t key)
    {
        if (!acceptKey(exchange, key))
            return false;
        if (route.vary.length != 0 && exchange.originCount != 0)
            return false;
        if (route.accept[key].contentType is null)
            return false;
        return route.bodyIndex == maxArguments || bodyAdmitted(exchange);
    }

    // Binds every argument, S5's body first (read, then validated by the processor's own code into `failure`);
    // false declines.
    private static bool bound(ref Route route, ref scope FastExchange exchange,
            ref const Span[maxArguments] values, ref Any[maxArguments] arguments, out Exception failure)
    {
        if (route.bodyIndex != maxArguments && !bindBody(route, exchange, arguments[route.bodyIndex]))
            return false;
        if (!bindArguments(route, exchange, values, arguments))
            return false;
        if (route.bodyIndex != maxArguments)
            failure = route.bodyProcessor.validationFailure(arguments[route.bodyIndex], route.bodyParameter);
        return true;
    }

    /++
    S2: a `ResponseEntity` as `HttpEntityMethodProcessor.handleReturnValue` writes it: the entity's status; no body,
    no `Content-Type` and `Content-Length: 0` without a body; otherwise the Jackson converter's body with the
    negotiated `Content-Type`, sent chunked because the processor flushes. An entity the fast path does not write
    exactly (headers of its own, no status, a body another converter would write) goes to that very processor on
    the materialized request and response: the handler has run, so the request can no longer be declined.
    +/
    private FastOutcome serveEntity(ref Route route, DispatcherServlet servlet,
            ref scope FastExchange exchange, Any result, size_t slot)
    {
        const entry = route.accept[slot];
        if (!result.holds!ResponseEntity)
            return completeReturn(servlet, exchange, route, result);
        auto entity = result.get!ResponseEntity;
        const status = entity.getStatusCode().value();
        auto content = entity.getBody();
        if (status == 0 || !entity.getHeaders().isEmpty() || (!content.isNull()
                && !writesBody(route, content.typeName(), slot)))
            return completeReturn(servlet, exchange, route, result);
        FastField[maxFields] storage;
        if (content.isNull())
        {
            exchange.respondFields(status, responseFields(route, exchange, null, storage), null, false);
            return FastOutcome.written;
        }
        auto buffer = pool.acquire();
        scope (exit)
            pool.release(buffer);
        try
            route.jackson.getMapper().writeValue(&buffer.put, content);
        catch (Exception e)
        {
            import flint.java.io : IOException;

            Exception ex = cast(IOException) e !is null ? e : new HttpMessageNotWritableException(
                    "Could not write JSON: " ~ e.msg, e);
            return complete(servlet, exchange, route, ex, status, entry.contentType, buffer.data);
        }
        exchange.respondFields(status, responseFields(route, exchange, entry.contentType, storage), buffer.data, true);
        return FastOutcome.written;
    }

    /// The handler returned `result`, which the fast path does not write: the generic return handling writes it.
    private static FastOutcome completeReturn(DispatcherServlet servlet,
            ref scope FastExchange exchange, ref Route route, Any result)
    {
        Object request, response;
        exchange.materialize(request, response);
        auto servletRequest = cast(HttpServletRequest) request;
        auto servletResponse = cast(HttpServletResponse) response;
        auto chain = servlet.prepareProvedCompletion(servletRequest, servletResponse,
                route.mapping.provedHandler(route.info, route.handler, servletRequest));
        auto processor = route.entityProcessor;
        auto returnType = route.handler.getReturnType();
        servlet.completeFastReturn(servletRequest, servletResponse, chain,
                (HttpServletRequest servletRequest, HttpServletResponse servletResponse) {
            processor.handleReturnValue(result, returnType, new ModelAndViewContainer,
                new ServletWebRequest(servletRequest, servletResponse));
        });
        return FastOutcome.materialized;
    }

    /// The handler ran and `ex` escaped: build the servlet objects and let the dispatcher resolve it.
    private static FastOutcome complete(DispatcherServlet servlet, ref scope FastExchange exchange,
            ref Route route, Exception ex, int status, string contentType, const(ubyte)[] partial)
    {
        Object request, response;
        exchange.materialize(request, response);
        auto servletRequest = cast(HttpServletRequest) request;
        auto servletResponse = cast(HttpServletResponse) response;
        // The interceptors' preHandle (CORS's Vary) comes before anything the handler's return wrote.
        auto chain = servlet.prepareProvedCompletion(servletRequest, servletResponse,
                route.mapping.provedHandler(route.info, route.handler, servletRequest));
        // HttpEntityMethodProcessor sets the entity's status before it writes.
        if (status != 0)
            servletResponse.setStatus(status);
        if (partial.length != 0)
        {
            servletResponse.setContentType(contentType);
            servletResponse.getOutputStream().write(partial);
        }
        servlet.completeFastDispatch(servletRequest, servletResponse, chain, ex);
        return FastOutcome.materialized;
    }
}

/++
Flint addition: the dispatcher's side of the error-page shortcut (fast-path.md, "The error-page shortcut").

`prove` checks once, against the strategies themselves, what the generic ERROR dispatch of a request to the error
path does for each `Accept` key:
$(UL
    $(LI the first handler mapping finds the error path among its plain paths, has no interceptors, and every
        registration there has no condition but the path and at most one `produces` type; for the key, the
        registrations whose `produces` matches compare as `lookupHandlerMethod` sorts them, and `json` (Boot's
        `BasicErrorController.error`) is strictly first;)
    $(LI no CORS processing applies (`corsFields` with no `Vary`): no global configuration, none of its own;)
    $(LI the first adapter resolves its only parameter, the `HttpServletRequest`, to the request itself, and hands
        its `ResponseEntity` to exactly `HttpEntityMethodProcessor`;)
    $(LI that processor's negotiation (the header-only manager, which `WebMvcConfigurationSupport` always gives the
        adapter) selects a parameterless type that the Jackson converter is the first to write for `bodyType`.)
)
Flint has no `ResponseBodyAdvice` chain and no `@ModelAttribute` or `@InitBinder` advice, so nothing else acts on the
body.

`write` then writes what that processor writes for the controller's `ResponseEntity`: the status, the negotiated
`Content-Type`, the converter's own mapper's bytes, then the flush, so the engine frames it as the generic path does.
For anything it does not write exactly it writes nothing and answers `false`, and the caller forwards generically.
+/
final class ErrorShortcutRoute
{
    private string bodyType;
    private AcceptEntry[acceptKeys.length] accept;
    private JacksonJsonHttpMessageConverter jackson;
    private BodyPool pool;

    private this(string bodyType)
    {
        this.bodyType = bodyType;
        pool = new BodyPool;
    }

    /// The route for `servlet`'s ERROR dispatch to `errorPath` choosing the handler `json` selects, whose body is a
    /// `bodyType`; `null` when any condition above fails.
    static ErrorShortcutRoute prove(DispatcherServlet servlet, string errorPath, string bodyType,
            scope bool delegate(HandlerMethod) @safe json)
    {
        RequestMappingInfoHandlerMapping mappings;
        RequestMappingHandlerAdapter adapter;
        ErrorRegistrations registrations;
        if (!firstStrategies(servlet, mappings, adapter))
            return null;
        if (!registrations.collect(mappings, errorPath, json) || !plainHandler(registrations.json, mappings, adapter))
            return null;
        auto converters = adapter.getMessageConverters();
        auto producible = AbstractMessageConverterMethodProcessor.producibleTypes(converters, bodyType);
        auto route = new ErrorShortcutRoute(bodyType);
        foreach (slot, key; acceptKeys)
        {
            if (!registrations.chooseJson(key))
                continue;
            if (auto writer = acceptEntry(key, producible, bodyType, false, converters, route.accept[slot]))
                route.jackson = writer;
        }
        return route.jackson !is null ? route : null;
    }

    /// The Jackson converter's mapper, which writes every body: the caller proves it is the application's stock one.
    Object converterMapper()
    {
        return cast(Object) jackson.getMapper();
    }

    /++
    The `acceptKeys` slot of `request`'s one `Accept` field (slot 0 without one), when the route writes it; `false`
    for several fields, another value, or a key the dispatch would not answer with the Jackson converter.
    +/
    bool admits(HttpServletRequest request, out size_t slot)
    {
        size_t count;
        string value;
        if (auto source = cast(HeaderFieldSource) request)
            source.visitHeaderFields((string name, string field) {
                if (equalsAsciiIgnoreCase(name, HttpHeaders.ACCEPT))
                {
                    ++count;
                    value = field;
                }
            });
        else
        {
            auto values = request.getHeaders(HttpHeaders.ACCEPT);
            count = values.length;
            value = count != 0 ? values[0] : null;
        }
        if (count > 1)
            return false;
        if (count == 1)
        {
            slot = acceptKeys.length;
            foreach (index, candidate; acceptKeys[1 .. $])
                if (value == candidate)
                    slot = index + 1;
            if (slot == acceptKeys.length)
                return false;
        }
        return accept[slot].contentType !is null;
    }

    /++
    Write `entity`, which the error controller returned for an admitted request in `slot`, as
    `HttpEntityMethodProcessor` writes it: `setStatus`, then (at the body) the `Content-Type`, the body, and
    `flushBuffer`. `false`, having written nothing, for an entity with headers, without a status or body, or with a
    body of another type, and when the mapper fails: the generic forward then does exactly that.
    +/
    bool write(HttpServletResponse response, size_t slot, ResponseEntity entity)
    {
        const entry = accept[slot];
        const status = entity.getStatusCode().value();
        auto content = entity.getBody();
        if (entry.contentType is null || status == 0 || !entity.getHeaders().isEmpty()
                || content.isNull() || content.typeName() != bodyType)
            return false;
        auto buffer = pool.acquire();
        scope (exit)
            pool.release(buffer);
        try
            jackson.getMapper().writeValue(&buffer.put, content);
        catch (Exception)
            return false;
        response.setStatus(status);
        response.setContentType(entry.contentType);
        response.getOutputStream().write(buffer.data);
        response.flushBuffer();
        return true;
    }

    /// S6: `admits` for the request `exchange` holds.
    bool admits(ref scope FastExchange exchange, out size_t slot)
    {
        return acceptKey(exchange, slot) && accept[slot].contentType !is null;
    }

    /++
    S6: `write` straight to `exchange`, for a request whose response holds only the mapped filters' fields: the
    status, those fields then the `Content-Type`, the mapper's bytes, flushed (chunked), as `write` leaves the
    servlet response for the engine to frame.
    +/
    bool write(ref scope FastExchange exchange, size_t slot, ResponseEntity entity)
    {
        const entry = accept[slot];
        const status = entity.getStatusCode().value();
        auto content = entity.getBody();
        if (entry.contentType is null || status == 0 || !entity.getHeaders().isEmpty()
                || content.isNull() || content.typeName() != bodyType)
            return false;
        auto buffer = pool.acquire();
        scope (exit)
            pool.release(buffer);
        try
            jackson.getMapper().writeValue(&buffer.put, content);
        catch (Exception)
            return false;
        Route plain;
        FastField[maxFields] storage;
        exchange.respondFields(status, responseFields(plain, exchange, entry.contentType, storage), buffer.data, true);
        return true;
    }

    /++
    S6, the template body: the bytes `write` would send for `entity` (its body, by the converter's mapper), copied;
    `false` when `write` would decline it. The caller proves a body template against them at startup.
    +/
    bool render(ResponseEntity entity, out const(ubyte)[] bytes)
    {
        auto content = entity.getBody();
        if (entity.getStatusCode().value() == 0 || !entity.getHeaders().isEmpty()
                || content.isNull() || content.typeName() != bodyType)
            return false;
        auto buffer = pool.acquire();
        scope (exit)
            pool.release(buffer);
        try
            jackson.getMapper().writeValue(&buffer.put, content);
        catch (Exception)
            return false;
        bytes = buffer.data.idup;
        return true;
    }

    /++
    S6, the template body: `write` for an entity of `status` whose body the mapper writes as `content` (the caller
    proved them equal), for a request `admits` admitted in `slot`.
    +/
    void write(ref scope FastExchange exchange, size_t slot, int status, scope const(ubyte)[] content)
    {
        Route plain;
        FastField[maxFields] storage;
        exchange.respondFields(status, responseFields(plain, exchange, accept[slot].contentType,
                storage), content, true);
    }

    /++
    S6: whether the dispatch of a `GET` that `servlet`'s first handler mapping does not match ends, through
    `doDispatch`, in exactly `sendError(404)` with nothing else written or set on the response. It holds when:
    $(UL
        $(LI the handler mappings are exactly that mapping and the stock resource mapping (`/**` to an exact
            `ResourceHttpRequestHandler`, no interceptors, no CORS), whose handler raises `NoResourceFoundException`
            through an exact `HttpRequestHandlerAdapter`, the first adapter that supports it;)
        $(LI the exception resolvers are `recordsOnly` (a resolver that only records the exception, Boot's
            `DefaultErrorAttributes`), then exactly Spring's three: `ExceptionHandlerExceptionResolver` with no advice
            (which leaves a resource handler's exceptions alone), `ResponseStatusExceptionResolver` finding no
            `@ResponseStatus` on `NoResourceFoundException` or its bases, and `DefaultHandlerExceptionResolver`, which
            sends `ErrorResponse`'s status and detail with no headers; none of them adds `Cache-Control`.)
    )
    The detail message and the request attributes the dispatch leaves are the error page's to prove unread.
    +/
    static bool provesUnmatched(DispatcherServlet servlet, scope bool delegate(Object) @safe recordsOnly, out string why)
    {
        import flint.http : HttpMethod;
        import flint.web.servlet.mvc.annotation : ResponseStatusExceptionResolver;
        import flint.web.servlet.mvc.method.annotation : ExceptionHandlerExceptionResolver;
        import flint.web.servlet.mvc.support : DefaultHandlerExceptionResolver;
        import flint.web.servlet.resource : HttpRequestHandlerAdapter, NoResourceFoundException,
            provedResourceFallback;

        bool fails(string reason)
        {
            why = reason;
            return false;
        }

        auto strategies = &servlet.proofStrategies();
        if (strategies.handlerMappings.length != 2 || !provedResourceFallback(strategies.handlerMappings[1]))
            return fails("handler mappings");
        // getHandlerAdapter takes the first that supports the resource handler: the request mapping adapter
        // supports only handler methods, so it is the HttpRequestHandlerAdapter, exactly.
        auto adapters = strategies.handlerAdapters;
        if (adapters.length < 2 || typeid(cast(Object) adapters[0]) !is typeid(RequestMappingHandlerAdapter)
                || typeid(cast(Object) adapters[1]) !is typeid(HttpRequestHandlerAdapter))
            return fails("handler adapters");
        auto resolvers = strategies.handlerExceptionResolvers;
        if (resolvers.length != 4 || !recordsOnly(cast(Object) resolvers[0]))
            return fails("exception resolvers");
        // DefaultHandlerExceptionResolver copies the exception's headers before sendError: it has none.
        if (!new NoResourceFoundException(HttpMethod.GET, "/", "").getHeaders().isEmpty())
            return fails("NoResourceFoundException headers");
        auto handlers = cast(ExceptionHandlerExceptionResolver) resolvers[1];
        auto status = cast(ResponseStatusExceptionResolver) resolvers[2];
        auto defaults = cast(DefaultHandlerExceptionResolver) resolvers[3];
        if (handlers is null || typeid(handlers) !is typeid(ExceptionHandlerExceptionResolver)
                || !handlers.leavesResourceHandlers())
            return fails("ExceptionHandlerExceptionResolver");
        if (status is null || typeid(status) !is typeid(ResponseStatusExceptionResolver)
                || !status.resolvesNothingFor(typeid(NoResourceFoundException)))
            return fails("ResponseStatusExceptionResolver");
        if (defaults is null || typeid(defaults) !is typeid(DefaultHandlerExceptionResolver))
            return fails("DefaultHandlerExceptionResolver");
        if (handlers.preventsResponseCaching() || status.preventsResponseCaching() || defaults.preventsResponseCaching())
            return fails("Cache-Control");
        return true;
    }
}

// The first handler mapping and adapter, which `getHandler` and `getHandlerAdapter` consult first, when they are
// the request-mapping ones and the mapping has no interceptors.
private bool firstStrategies(DispatcherServlet servlet, out RequestMappingInfoHandlerMapping mappings,
        out RequestMappingHandlerAdapter adapter)
{
    auto strategies = &servlet.proofStrategies();
    if (strategies.handlerMappings.length == 0 || strategies.handlerAdapters.length == 0)
        return false;
    mappings = cast(RequestMappingInfoHandlerMapping) strategies.handlerMappings[0];
    adapter = cast(RequestMappingHandlerAdapter) strategies.handlerAdapters[0];
    return mappings !is null && adapter !is null && mappings.getAdaptedInterceptors().length == 0;
}

// No CORS processing applies to `handler`, its only parameter is the request itself, and its `ResponseEntity` goes
// to exactly `HttpEntityMethodProcessor`.
private bool plainHandler(HandlerMethod handler, RequestMappingInfoHandlerMapping mappings,
        RequestMappingHandlerAdapter adapter)
{
    Route cors;
    if (!corsFields(handler, mappings, cors) || cors.vary.length != 0)
        return false;
    return requestOnly(handler, adapter) && entityReturn(handler, adapter);
}

/// The registrations `lookupHandlerMethod` finds by the error path, and the JSON handler among them.
private struct ErrorRegistrations
{
    RequestMappingInfo[] infos;
    HandlerMethod[] handlers;
    HandlerMethod json;
    size_t jsonIndex;

    // Every registration at `errorPath` has only the path and at most one `produces` type (so a match is the
    // registration itself, not a narrowed copy), and exactly one is the JSON handler.
    bool collect(RequestMappingInfoHandlerMapping mappings, string errorPath,
            scope bool delegate(HandlerMethod) @safe isJson)
    {
        bool plain = true;
        mappings.visitDirectPath(errorPath, (RequestMappingInfo info, HandlerMethod handler) {
            plain = plain && info.pathAndProducesOnly() && info.getProducibleMediaTypes().length <= 1;
            infos ~= info;
            handlers ~= handler;
        });
        if (!plain)
            return false;
        foreach (index, handler; handlers)
        {
            if (!isJson(handler))
                continue;
            if (json !is null)
                return false;
            json = handler;
            jsonIndex = index;
        }
        return json !is null;
    }

    // Whether the lookup for `key` (no field for null) chooses the JSON handler: it matches, and it compares
    // strictly first against every other match, so the sort puts it first and no ambiguity is raised. With only
    // paths and produces, `compareTo` between them is the produces comparison.
    bool chooseJson(string key)
    {
        string[] values = key is null ? null : [key];
        MediaType[] accepted;
        try
            accepted = HeaderContentNegotiationStrategy.resolveHeaderValues(values);
        catch (Exception)
            return false;
        auto mine = infos[jsonIndex];
        if (!mine.producesMatch(accepted))
            return false;
        foreach (index, info; infos)
            if (index != jsonIndex && info.producesMatch(accepted) && mine.compareProducesFor(info, accepted) >= 0)
                return false;
        return true;
    }
}

// The JSON handler's parameters are all the request itself, as `ServletRequestMethodArgumentResolver` resolves an
// `HttpServletRequest` (the native request of the dispatch).
private bool requestOnly(HandlerMethod handler, RequestMappingHandlerAdapter adapter)
{
    foreach (parameter; handler.getMethodParameters())
    {
        auto resolver = adapter.getArgumentResolvers().getArgumentResolver(parameter);
        if (resolver is null || typeid(cast(Object) resolver) !is typeid(ServletRequestMethodArgumentResolver)
                || parameter.getParameterType() != "flint.jakarta.servlet.http.HttpServletRequest")
            return false;
    }
    return true;
}

// The first return value handler that supports the JSON handler's `ResponseEntity` is exactly
// `HttpEntityMethodProcessor`, as the composite selects it.
private bool entityReturn(HandlerMethod handler, RequestMappingHandlerAdapter adapter)
{
    auto returnType = handler.getReturnType();
    if (returnType.getParameterType() != "flint.http.ResponseEntity")
        return false;
    foreach (returnHandler; adapter.getReturnValueHandlers().getHandlers())
        if (returnHandler.supportsReturnType(returnType))
            return typeid(cast(Object) returnHandler) is typeid(HttpEntityMethodProcessor);
    return false;
}

private bool equalsAsciiIgnoreCase(scope const(char)[] a, scope const(char)[] b) pure nothrow @nogc
{
    if (a.length != b.length)
        return false;
    foreach (i, c; a)
    {
        const x = c >= 'A' && c <= 'Z' ? cast(char)(c + 32) : c;
        const y = b[i] >= 'A' && b[i] <= 'Z' ? cast(char)(b[i] + 32) : b[i];
        if (x != y)
            return false;
    }
    return true;
}

/++
The literal text a path pattern starts with, before its first variable, wildcard or escape (`{`, `*`, `?`, `%`):
every path the pattern matches starts with it, since the literal part of a pattern matches only itself.
+/
private string literalPrefix(string pattern) pure nothrow @nogc
{
    foreach (i, c; pattern)
        if (c == '{' || c == '*' || c == '?' || c == '%')
            return pattern[0 .. i];
    return pattern;
}

/++
Whether `path`, still percent-encoded, is its own lookup path: it starts with `/` and has no `%` (nothing to decode),
no `;` (no path parameters to strip), no empty segment and no `.` or `..` segment (nothing to normalize). Then the
literal prefixes compare with what the patterns are matched against.
+/
private bool plainPath(scope const(char)[] path) pure nothrow @nogc
{
    if (path.length == 0 || path[0] != '/')
        return false;
    size_t segmentStart = 1;
    foreach (i; 1 .. path.length + 1)
    {
        if (i < path.length && path[i] != '/')
        {
            if (path[i] == '%' || path[i] == ';' || path[i] == '\\')
                return false;
            continue;
        }
        const segment = path[segmentStart .. i];
        if ((segment.length == 0 && i < path.length) || segment == "." || segment == "..")
            return false;
        segmentStart = i + 1;
    }
    return true;
}

/// The `acceptKeys` slot of the request's one `Accept` field (slot 0 without one); `false` for several fields or a
/// value outside the keys.
private bool acceptKey(ref scope FastExchange exchange, out size_t key)
{
    if (exchange.acceptCount > 1)
        return false;
    if (exchange.acceptCount == 0)
        return true;
    foreach (index, candidate; acceptKeys[1 .. $])
        if (exchange.accept == candidate)
        {
            key = index + 1;
            return true;
        }
    return false;
}

/++
Each argument as its resolver binds it: a `@RequestParam string` by `bindString`, a path variable from the matched
template's `values` by `bindPathVariable`. `false`, before anything ran, when one of them declines.
+/
private bool bindArguments(ref const Route route, ref scope FastExchange exchange,
        ref const Span[maxArguments] values, ref Any[maxArguments] arguments)
{
    foreach (index, ref spec; route.arguments)
    {
        if (index == route.bodyIndex)
            continue; // bound by serve (bindBody)
        if (spec.kind == ArgumentKind.pathVariable)
        {
            const span = values[route.variableOf[index]];
            if (!bindPathVariable(exchange.path[span.start .. span.end], spec.type, arguments[index]))
                return false;
            continue;
        }
        string value;
        const defaultValue = spec.defaultValue == ValueConstants.DEFAULT_NONE ? null : spec.defaultValue;
        if (!bindString(exchange, spec.name, defaultValue, spec.required, value))
            return false;
        arguments[index] = Any.of(value);
    }
    return true;
}

/++
A path variable as `PathVariableMethodArgumentResolver` and the conversion service bind it, for the values the fast
path can bind exactly; every other value declines, and the generic path converts it (or answers the mismatch). An
`int` or `long` takes canonical decimal digits only: no sign, no leading zero, no hexadecimal form, and few enough
digits that the value fits. A `string` takes a segment without `%` (the generic path decodes it) or `;` (matrix
variables, which the generic path strips); it is copied to the GC heap, as it reaches user code.
+/
private bool bindPathVariable(scope const(char)[] text, string type, out Any value)
{
    switch (type)
    {
    case "int":
        long number;
        if (!canonicalDigits(text, 9, number))
            return false;
        value = Any.of(cast(int) number);
        return true;
    case "long":
        long number;
        if (!canonicalDigits(text, 18, number))
            return false;
        value = Any.of(number);
        return true;
    case "string":
        foreach (c; text)
            if (c == '%' || c == ';')
                return false;
        value = Any.of(text.idup);
        return true;
    default:
        return false;
    }
}

/// `text` as a decimal number of at most `maxDigits` digits, without a sign or a leading zero.
private bool canonicalDigits(scope const(char)[] text, size_t maxDigits, out long number) pure nothrow @nogc
{
    if (text.length == 0 || text.length > maxDigits || (text.length > 1 && text[0] == '0'))
        return false;
    foreach (c; text)
    {
        if (c < '0' || c > '9')
            return false;
        number = number * 10 + (c - '0');
    }
    return true;
}

/// The most arguments a fast route binds, on the stack; a handler with more stays generic.
private enum size_t maxArguments = 8;

/// The fields a fast response writes on the stack; more (many filter fields) take one GC copy.
private enum size_t maxFields = 16;

/++
The fields the generic response holds: the mapped filters' (S4: the security headers, which `HeaderWriterFilter`
writes before the servlet runs), the route's `Vary` fields (S3), then `Content-Type` when given.
+/
private const(FastField)[] responseFields(ref const Route route, ref scope FastExchange exchange,
        string contentType, return ref FastField[maxFields] storage)
{
    const count = exchange.filterFields.length + route.vary.length + (contentType !is null);
    FastField[] fields = count <= storage.length ? storage[0 .. count] : new FastField[count];
    size_t used;
    foreach (ref field; exchange.filterFields)
        fields[used++] = field;
    foreach (ref field; route.vary)
        fields[used++] = field;
    if (contentType !is null)
        fields[used++] = FastField("Content-Type", contentType);
    return fields;
}

/// Where a template variable's text lies in the request path.
private struct Span
{
    size_t start, end;
}

/// One segment of a route template: a literal, or the index of a `{name}` variable.
private struct Segment
{
    string literal;
    ptrdiff_t variable = -1;
}

/// One proved endpoint: the row's path, as a template when it has variables, its argument specs, and the handler
/// that invokes it.
private struct Route
{
    string path;
    /// Empty for a literal path, which is compared whole.
    Segment[] segments;
    HandlerMethod handler;
    const(ArgumentSpec)[] arguments;
    /// Per argument: the template variable a path variable binds.
    size_t[maxArguments] variableOf;
    JacksonJsonHttpMessageConverter jackson;
    /// S3: `DefaultCorsProcessor`'s `Vary` fields for a handler with a CORS configuration, else empty.
    FastField[] vary;
    /// S2: the adapter's `HttpEntityMethodProcessor` for a `ResponseEntity` return, else null.
    HttpEntityMethodProcessor entityProcessor;
    /// The adapter's converters, in order: for an entity's body the writer is chosen per request.
    HttpMessageConverter[] converters;
    /// Per `acceptKeys` slot: the entity body type `jacksonWrites` last proved, so a repeated type is not proved
    /// again (`writesBody`).
    ProvenBody[acceptKeys.length] provenBody;
    /// The method the route answers: `GET` (and `HEAD`), or (S5) `POST`.
    string method;
    /// The registration the lookup chooses for the route's requests, and its handler mapping: a hand-back builds the
    /// lookup's attributes and chain from them without a second lookup (`provedHandler`).
    RequestMappingInfo info;
    /// ditto
    RequestMappingInfoHandlerMapping mapping;
    /// S5: the `@RequestBody` argument's index (`maxArguments` without one), its parameter and declared type, the
    /// converter that reads it (exactly the Jackson converter) and the processor that validates it.
    size_t bodyIndex = maxArguments;
    /// ditto
    MethodParameter bodyParameter;
    /// ditto
    string bodyType;
    /// ditto
    JacksonJsonHttpMessageConverter reader;
    /// ditto
    RequestResponseBodyMethodProcessor bodyProcessor;
    /// Per `acceptKeys` slot: the `Content-Type` the generic path writes, or `null` where it does not write one.
    AcceptEntry[acceptKeys.length] accept;
}

private struct AcceptEntry
{
    string contentType;
    /// The selected type itself, for `canWrite`.
    MediaType selected;
}

/++
`jacksonWrites` for an entity body of `typeName` in `slot`, remembered: the slot keeps the first type it proved, in an
object that holds the name (so its memory is never reused for another name), published with one atomic store and
never changed. The same name, by pointer or by content, is then proved without asking the converters again; another
type is proved each time, as before.
+/
private bool writesBody(ref Route route, string typeName, size_t slot)
{
    import core.atomic : atomicLoad, cas;

    auto proven = atomicLoad(route.provenBody[slot]);
    if (proven !is null && (proven.name is typeName || proven.name == typeName))
        return true;
    if (!jacksonWrites(route, typeName, route.accept[slot]))
        return false;
    if (proven is null)
        cas(&route.provenBody[slot], cast(ProvenBody) null, new ProvenBody(typeName));
    return true;
}

// A body type `writesBody` proved; immutable once published.
private final class ProvenBody
{
    private string name;

    this(string name) pure nothrow @nogc
    {
        this.name = name;
    }
}

/// Whether the first converter that writes `typeName` as the entry's type is exactly the Jackson converter, as
/// `writeWithMessageConverters` picks it.
private bool jacksonWrites(ref Route route, string typeName, ref const AcceptEntry entry)
{
    MediaType selected = entry.selected;
    foreach (converter; route.converters)
        if (converter.canWrite(typeName, &selected))
            return typeid(cast(Object) converter) is typeid(JacksonJsonHttpMessageConverter);
    return false;
}

/++
`path` as a template the fast path matches byte for byte: literal segments without pattern syntax, escapes or matrix
parameters, and whole-segment `{name}` variables without a regular expression. `segments` stays empty for a path
without variables. `false` for anything else, which the generic `PathPattern` keeps.
+/
private bool parseTemplate(string path, out Segment[] segments, out string[] variables)
{
    if (path.length == 0 || path[0] != '/')
        return false;
    Segment[] parsed;
    size_t start = 1;
    while (start <= path.length)
    {
        size_t end = start;
        while (end < path.length && path[end] != '/')
            ++end;
        Segment segment;
        if (!parseSegment(path[start .. end], segment, variables))
            return false;
        parsed ~= segment;
        start = end + 1;
    }
    if (variables.length != 0)
        segments = parsed;
    return true;
}

// One template segment: `{name}` (a word name) becomes the next variable, anything else must be a plain literal.
private bool parseSegment(string text, ref Segment segment, ref string[] variables)
{
    if (text.length > 2 && text[0] == '{' && text[$ - 1] == '}')
    {
        foreach (c; text[1 .. $ - 1])
            if (!(c == '_' || (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')))
                return false;
        segment.variable = variables.length;
        variables ~= text[1 .. $ - 1];
        return true;
    }
    foreach (c; text)
        if (c == '{' || c == '}' || c == '*' || c == '?' || c == '%' || c == ';' || c == '\\')
            return false;
    segment.literal = text;
    return true;
}

/// Whether `path` matches the template, every variable a non-empty segment; where each variable's text lies goes
/// to `values`.
private bool matchTemplate(scope const(char)[] path, const(Segment)[] segments, ref Span[maxArguments] values)
{
    if (path.length == 0 || path[0] != '/')
        return false;
    size_t start = 1;
    foreach (index, ref segment; segments)
    {
        size_t end = start;
        while (end < path.length && path[end] != '/')
            ++end;
        const last = index + 1 == segments.length;
        if (last ? end != path.length : end >= path.length)
            return false;
        const text = path[start .. end];
        if (segment.variable < 0 ? text != segment.literal : text.length == 0)
            return false;
        if (segment.variable >= 0)
            values[segment.variable] = Span(start, end);
        start = end + 1;
    }
    return true;
}

/++
The mapping proof (fast-path.md): the row is a `GET` of one literal or template path without other conditions
(`produces` only as exactly `application/json`), `@ResponseBody`, without `@ResponseStatus` or `@CrossOrigin`; the
generic lookup finds exactly this handler for every path the route accepts; every parameter goes to the
`@RequestParam` resolver as a `string` or to the `@PathVariable` resolver as an `int`, `long` or `string`; and each
`Accept` slot selects a parameterless media type that the Jackson converter writes. A slot that the generic path
answers some other way (406, another converter, a charset) is left empty, so those requests take the generic path.
+/
private bool prove(ref const AotHandlerMapping row, RequestMappingInfoHandlerMapping mappings,
        RequestMappingHandlerAdapter adapter, out Route route)
{
    if (!simpleRow(row))
        return false;
    route.path = row.paths[0];
    route.method = row.methods[0];
    string[] variables;
    if (!parseTemplate(route.path, route.segments, variables))
        return false;
    route.handler = variables.length == 0 ? directHandler(route.path, route.method, mappings,
            route.info) : patternHandler(row, route.segments, mappings, route.info);
    route.mapping = mappings;
    auto handler = route.handler;
    if (!invocableRow(handler, row))
        return false;
    if (!returnHandling(row, handler, adapter, route) || !boundArguments(row, handler, adapter,
            variables, route) || !corsFields(handler, mappings, route))
        return false;
    // S5: a POST route binds exactly one body; a GET route none.
    if ((route.method == "POST") != (route.bodyIndex != maxArguments))
        return false;
    route.arguments = row.arguments;
    return acceptTable(row, adapter, route);
}

// The row's own handler, invoked through its array invoker with at most `maxArguments` arguments, on a bean, with a
// return value and no @ResponseStatus.
private bool invocableRow(HandlerMethod handler, ref const AotHandlerMapping row)
{
    if (handler is null || handler.getArrayInvoker() !is row.invokeArguments || !handler.invokesArguments())
        return false;
    if (row.arguments.length > maxArguments || handler.getBean() is null || handler.isVoid())
        return false;
    return handler.getResponseStatus() == 0 && handler.getResponseStatusReason() is null;
}

// One GET path without consumes, or (S5) one POST path consuming exactly application/json; no params or headers,
// produces at most application/json, @ResponseBody without a status. A @CrossOrigin handler's CORS processing is
// proved by corsFields (S3).
private bool simpleRow(ref const AotHandlerMapping row)
{
    if (row.paths.length != 1 || row.params.length || row.headers.length)
        return false;
    if (!row.responseBody || row.responseStatus != 0)
        return false;
    if (row.produces.length != 0 && row.produces != ["application/json"])
        return false;
    if (row.methods == ["GET"])
        return row.consumes.length == 0;
    return row.methods == ["POST"] && row.consumes == ["application/json"];
}

/++
S3: what CORS processing does to a request without an `Origin` field. Without a global configuration source (the
table needs none) and without a configuration of its own, nothing. With one (its `@CrossOrigin`), `getHandler` adds
the CORS interceptor, whose processor must be exactly `DefaultCorsProcessor` (the default when none is set) and
whose configuration must validate (`validateAllowCredentials`, which `getHandler` runs per request): its `preHandle`
then adds the three `Vary` fields and lets the request through, as it is not a CORS request.
+/
private bool corsFields(HandlerMethod handler, RequestMappingInfoHandlerMapping mappings, ref Route route)
{
    if (mappings.hasGlobalCorsConfiguration())
        return false;
    auto config = mappings.registeredCorsConfiguration(handler);
    if (config is null)
        return true;
    auto processor = mappings.getCorsProcessor();
    if (processor !is null && typeid(cast(Object) processor) !is typeid(DefaultCorsProcessor))
        return false;
    try
        config.validateAllowCredentials();
    catch (Exception)
        return false;
    // DefaultCorsProcessor.processRequest's fields, by the same constants, in its order.
    route.vary = [
        FastField(HttpHeaders.VARY, HttpHeaders.ORIGIN),
        FastField(HttpHeaders.VARY, HttpHeaders.ACCESS_CONTROL_REQUEST_METHOD),
        FastField(HttpHeaders.VARY, HttpHeaders.ACCESS_CONTROL_REQUEST_HEADERS),
    ];
    return true;
}

// The one registration lookupHandlerMethod finds by the plain path for `method`, before it scans any pattern: the
// only one there whose methods condition the request reaches (GET routes count HEAD too); null otherwise. A POST
// registration must also consume exactly application/json, the Content-Type the route admits.
private HandlerMethod directHandler(string path, string method,
        RequestMappingInfoHandlerMapping mappings, out RequestMappingInfo registered)
{
    size_t found;
    HandlerMethod handler;
    bool consumesJson = true;
    mappings.visitDirectPath(path, (RequestMappingInfo info, HandlerMethod candidate) {
        if (!reachedBy(info, method))
            return;
        ++found;
        handler = candidate;
        registered = info;
        consumesJson = consumesRouteType(info, method);
    });
    return found == 1 && consumesJson ? handler : null;
}

/++
The registration of `row`'s template, when no other registration that the route's method (`GET` with `HEAD`, or S5's
`POST`) can reach could match a path the route accepts: then lookupHandlerMethod's scan finds this one alone for
every such path. null otherwise.
+/
private HandlerMethod patternHandler(ref const AotHandlerMapping row, const(Segment)[] segments,
        RequestMappingInfoHandlerMapping mappings, out RequestMappingInfo registered)
{
    auto infos = mappings.getHandlerMethods();
    auto handlers = mappings.mappedHandlerMethods();
    if (infos.length != handlers.length)
        return null;
    size_t found;
    HandlerMethod handler;
    foreach (index, info; infos)
        foreach (pattern; info.getPatterns())
            if (pattern.getPatternString() == row.paths[0] && handlers[index].getArrayInvoker() is row.invokeArguments)
            {
                ++found;
                handler = handlers[index];
                registered = info;
            }
    if (found != 1)
        return null;
    const method = row.methods[0];
    if (!consumesRouteType(registered, method))
        return null;
    const numeric = numericVariables(row, segments);
    foreach (index, info; infos)
    {
        if (handlers[index] is handler || !reachedBy(info, method))
            continue;
        foreach (pattern; info.getPatterns())
            if (mayOverlap(segments, numeric, pattern.getPatternString()))
                return null;
    }
    return handler;
}

// S5: a POST registration consumes exactly application/json, the Content-Type its route admits; a GET one is not
// asked.
private bool consumesRouteType(RequestMappingInfo info, string method)
{
    if (method != "POST")
        return true;
    auto consumable = info.getConsumableMediaTypes();
    return consumable.length == 1 && consumable[0] == MediaType.APPLICATION_JSON;
}

// Whether `info`'s method condition admits a route's requests: GET or HEAD for a GET route, POST for a POST route
// (none admits every method).
private bool reachedBy(RequestMappingInfo info, string routeMethod)
{
    auto methods = info.getMethods();
    if (methods.length == 0)
        return true;
    foreach (method; methods)
    {
        const name = method.name();
        if (routeMethod == "GET" ? name == "GET" || name == "HEAD" : name == routeMethod)
            return true;
    }
    return false;
}

// Whether a route answers requests of `method`: a GET route answers HEAD too (Spring maps HEAD to GET handlers).
private bool answers(ref const Route route, scope const(char)[] method)
{
    return route.method == "GET" ? method == "GET" || method == "HEAD" : method == route.method;
}

// S5: the body is offered whole, with exactly one Content-Type field whose value is the one key the route admits.
private bool bodyAdmitted(ref scope FastExchange exchange)
{
    return exchange.requestBody.length != 0 && exchange.contentTypeCount == 1
        && exchange.contentType == "application/json";
}

/++
S5: the body as `RequestResponseBodyMethodProcessor` reads it: the Jackson converter's `readInternal`, its mapper's
`readValue` of the body as the declared type. The body is copied first, as the servlet request's `readAllBytes`
copies it, so nothing the handler keeps points into the container's buffer. Any failure, or a JSON `null`,
declines: reading has no side effect, and the generic path then reads the body again and answers it.
+/
private bool bindBody(ref Route route, ref scope FastExchange exchange, out Any value)
{
    const content = exchange.requestBody.dup;
    try
        value = route.reader.getMapper().readValue(content, route.bodyType);
    catch (Exception)
        return false;
    return !value.isNull();
}

// Per template variable: whether the route only accepts canonical digits there (it binds an int or a long).
private bool[] numericVariables(ref const AotHandlerMapping row, const(Segment)[] segments)
{
    size_t count;
    foreach (ref segment; segments)
        if (segment.variable >= 0)
            ++count;
    auto numeric = new bool[count];
    foreach (ref spec; row.arguments)
    {
        if (spec.kind != ArgumentKind.pathVariable || (spec.type != "int" && spec.type != "long"))
            continue;
        foreach (ref segment; segments)
            if (segment.variable >= 0 && templateText(row.paths[0], segment.variable) == "{" ~ spec.name ~ "}")
                numeric[segment.variable] = true;
    }
    return numeric;
}

// The text of the `variable`-th `{name}` segment of `path`.
private string templateText(string path, ptrdiff_t variable)
{
    ptrdiff_t seen = -1;
    size_t start = 1;
    while (start <= path.length)
    {
        size_t end = start;
        while (end < path.length && path[end] != '/')
            ++end;
        const text = path[start .. end];
        if (text.length > 2 && text[0] == '{' && ++seen == variable)
            return text;
        start = end + 1;
    }
    return null;
}

/++
Whether a path the template accepts could also match `pattern`: segment by segment, a pattern segment with syntax
(a variable, `*` or `?`) can match anything, and a literal segment matches only itself, or a template variable
that accepts it (a numeric variable accepts canonical digits only). `**` and `{*name}` can match any number of
segments, so they always may overlap.
+/
private bool mayOverlap(const(Segment)[] segments, const(bool)[] numeric, string pattern)
{
    if (pattern.length == 0 || pattern[0] != '/')
        return true;
    size_t start = 1, index;
    while (start <= pattern.length)
    {
        size_t end = start;
        while (end < pattern.length && pattern[end] != '/')
            ++end;
        const text = pattern[start .. end];
        if (text == "**" || (text.length > 1 && text[0] == '{' && text[1] == '*'))
            return true;
        if (index >= segments.length)
            return false;
        bool syntax;
        foreach (c; text)
            syntax = syntax || c == '{' || c == '*' || c == '?';
        const segment = segments[index];
        if (!syntax)
        {
            long ignored;
            if (segment.variable < 0 ? text != segment.literal : numeric[segment.variable]
                    && !canonicalDigits(text, 18, ignored))
                return false;
        }
        ++index;
        start = end + 1;
    }
    return index == segments.length;
}

// invokeAndHandle sends ResponseEntity, HttpEntity and HttpHeaders returns to their own handlers before
// @ResponseBody, and those take status and headers from the value; ProblemDetail takes its own status and
// application/problem+json (web-http's review). The fast path writes a plain @ResponseBody value, and (S2) a
// ResponseEntity whose handler is exactly HttpEntityMethodProcessor, on a mapping whose produces condition fixes
// the producible type to application/json.
private bool returnHandling(ref const AotHandlerMapping row, HandlerMethod handler,
        RequestMappingHandlerAdapter adapter, ref Route route)
{
    enum entity = "flint.http.ResponseEntity";
    auto returnType = handler.getReturnType();
    foreach (returnHandler; adapter.getReturnValueHandlers().getHandlers())
    {
        if (!returnHandler.supportsReturnType(returnType) || (cast(HttpEntityMethodProcessor) returnHandler is null
                && cast(HttpHeadersReturnValueHandler) returnHandler is null))
            continue;
        if (row.returnType != entity || row.produces != ["application/json"]
                || typeid(cast(Object) returnHandler) !is typeid(HttpEntityMethodProcessor))
            return false;
        route.entityProcessor = cast(HttpEntityMethodProcessor) returnHandler;
        return true;
    }
    return row.returnType != entity && plainBody(row);
}

/++
Every parameter goes to the resolver the fast path binds as: `RequestParamMethodArgumentResolver` for a
`@RequestParam string`, `PathVariableMethodArgumentResolver` for a `@PathVariable` `int`, `long` or `string` named by
a template variable (the resolver composite's own lookup, as the generic path asks it).
+/
private bool boundArguments(ref const AotHandlerMapping row, HandlerMethod handler,
        RequestMappingHandlerAdapter adapter, const(string)[] variables, ref Route route)
{
    auto parameters = handler.getMethodParameters();
    if (parameters.length != row.arguments.length)
        return false;
    foreach (index, parameter; parameters)
    {
        auto resolver = adapter.getArgumentResolvers().getArgumentResolver(parameter);
        if (resolver is null)
            return false;
        const spec = row.arguments[index];
        const type = parameter.getParameterType();
        if (spec.kind == ArgumentKind.requestBody)
        {
            if (!bodyArgument(index, parameter, cast(Object) resolver, adapter, route))
                return false;
            continue;
        }
        if (typeid(cast(Object) resolver) is typeid(RequestParamMethodArgumentResolver))
        {
            if (spec.kind != ArgumentKind.requestParam || type != "string")
                return false;
            continue;
        }
        if (!pathArgument(index, spec, type, cast(Object) resolver, variables, route))
            return false;
    }
    return true;
}

// S1: a `@PathVariable` `int`, `long` or `string` resolved by exactly `PathVariableMethodArgumentResolver` and named
// by a template variable, whose index the route records.
private bool pathArgument(size_t index, ref const ArgumentSpec spec, string type, Object resolver,
        const(string)[] variables, ref Route route)
{
    if (typeid(resolver) !is typeid(PathVariableMethodArgumentResolver)
            || spec.kind != ArgumentKind.pathVariable || (type != "int" && type != "long" && type != "string"))
        return false;
    foreach (variable, name; variables)
        if (name == spec.name)
        {
            route.variableOf[index] = variable;
            return true;
        }
    return false;
}

/++
S5: a `@RequestBody` parameter of a POST route, as the generic path resolves it: exactly
`RequestResponseBodyMethodProcessor` (whose own `validationFailure` the route calls), a required, non-`Optional` body,
and as the first converter that reads the declared type as `application/json` (`readWithMessageConverters`' choice
for the one Content-Type the route admits), exactly the Jackson converter. One body per route.
+/
private bool bodyArgument(size_t index, MethodParameter parameter, Object resolver,
        RequestMappingHandlerAdapter adapter, ref Route route)
{
    auto processor = cast(RequestResponseBodyMethodProcessor) resolver;
    if (route.method != "POST" || route.bodyIndex != maxArguments || processor is null
            || typeid(processor) !is typeid(RequestResponseBodyMethodProcessor)
            || !parameter.getArgumentSpec().required || parameter.isOptional())
        return false;
    const type = parameter.getNestedParameterType();
    MediaType json = MediaType.APPLICATION_JSON;
    foreach (converter; adapter.getMessageConverters())
    {
        if (!converter.canRead(type, &json))
            continue;
        if (typeid(cast(Object) converter) !is typeid(JacksonJsonHttpMessageConverter))
            return false;
        route.reader = cast(JacksonJsonHttpMessageConverter) converter;
        route.bodyIndex = index;
        route.bodyParameter = parameter;
        route.bodyType = type;
        route.bodyProcessor = processor;
        return true;
    }
    return false;
}

/++
For each `Accept` key, the generic negotiation's answer: `HeaderContentNegotiationStrategy`'s parse and sort, then
`selectMediaType` over the producible types (the `produces` condition's, as `handleMatch` sets them, else the
converters'). Only a parameterless concrete type that `JacksonJsonHttpMessageConverter` writes gets an entry.
+/
private bool acceptTable(ref const AotHandlerMapping row, RequestMappingHandlerAdapter adapter, ref Route route)
{
    const valueType = row.returnType;
    auto converters = adapter.getMessageConverters();
    auto producible = row.produces.length != 0 ? MediaType.parseMediaTypes(
            ["application/json"]) : AbstractMessageConverterMethodProcessor.producibleTypes(converters, valueType);
    if (producible.length == 0)
        return false;
    JacksonJsonHttpMessageConverter jackson;
    foreach (slot, key; acceptKeys)
        if (auto writer = acceptEntry(key, producible, valueType, route.entityProcessor !is null,
                converters, route.accept[slot]))
            jackson = writer;
    route.jackson = jackson;
    route.converters = converters;
    return jackson !is null;
}

/++
One `Accept` key's negotiation, as `writeWithMessageConverters` runs it with the header-only negotiation manager:
`HeaderContentNegotiationStrategy`'s parse and sort, `selectMediaType` over `producible`, then the first converter
that writes `valueType` as the selected type. The Jackson converter, with `entry` filled, when it is that converter
and the type is concrete and parameterless; `null` otherwise, and the key takes the generic path. For an `entity`
the body type is known per request (`jacksonWrites`), so the writer is the Jackson converter itself.
+/
private JacksonJsonHttpMessageConverter acceptEntry(string key, MediaType[] producible,
        string valueType, bool entity, HttpMessageConverter[] converters, out AcceptEntry entry)
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
            return null;
        MimeTypeUtils.sortBySpecificity(acceptable);
        if (acceptable.length == 0)
            acceptable = [MediaType.ALL];
    }
    MediaType selected;
    if (AbstractMessageConverterMethodProcessor.selectMediaType(acceptable, producible, valueType,
            selected) != AbstractMessageConverterMethodProcessor.Selection.selected)
        return null;
    selected = selected.removeQualityValue();
    // AbstractHttpMessageConverter.addDefaultHeaders keeps a concrete type other than octet-stream as it is.
    if (!selected.isConcrete() || selected.equals(MediaType.APPLICATION_OCTET_STREAM))
        return null;
    HttpMessageConverter writer;
    foreach (converter; converters)
    {
        const candidate = entity ? typeid(cast(Object) converter) is typeid(JacksonJsonHttpMessageConverter)
            : converter.canWrite(valueType, &selected);
        if (candidate)
        {
            writer = converter;
            break;
        }
    }
    if (writer is null || typeid(cast(Object) writer) !is typeid(JacksonJsonHttpMessageConverter))
        return null;
    const header = selected.toString();
    foreach (c; header)
        if (c == ';')
            return null;
    entry = AcceptEntry(header, selected);
    return cast(JacksonJsonHttpMessageConverter) writer;
}

/// Whether the declared return type is a plain value: not `Object`, `Any` or `ProblemDetail` (or a subtype).
private bool plainBody(ref const AotHandlerMapping row)
{
    enum problem = "flint.http.ProblemDetail";
    if (row.returnType == "object.Object" || row.returnType == "flint.engine.aot.any.Any" || row.returnType == problem)
        return false;
    if (row.returnDescriptor !is null)
        foreach (supertype; row.returnDescriptor.supertypes)
            if (supertype == problem)
                return false;
    return true;
}

/++
`@RequestParam String` binding as the generic path does it: `RequestParamMethodArgumentResolver.resolveName` reads
every value (then `name[]`), `AbstractNamedValueMethodArgumentResolver` applies the default to an absent or empty
single value, and the conversion service joins several values with `,`. The query is decoded once, straight into
a stack buffer; the value is copied to the GC heap in one allocation, because it reaches user code; a default is
the generated literal itself. A joined value past the buffer declines to the generic path.
+/
private bool bindString(ref scope FastExchange exchange, string name, string defaultValue,
        bool required, out string value)
{
    char[1024] stack = void;
    size_t count, at;
    bool overflow;
    void collect(scope const(char)[] text)
    {
        if (overflow)
            return;
        const separator = count++ != 0;
        if (at + separator + text.length > stack.length)
        {
            overflow = true;
            return;
        }
        if (separator)
            stack[at++] = ',';
        stack[at .. at + text.length] = text;
        at += text.length;
    }

    char[64] arrayName = void;
    const(char)[] lookup = name;
    if (!exchange.parameter(lookup, &collect))
        return false;
    if (count == 0)
    {
        if (name.length + 2 > arrayName.length)
            return false;
        arrayName[0 .. name.length] = name;
        arrayName[name.length .. name.length + 2] = "[]";
        lookup = arrayName[0 .. name.length + 2];
        if (!exchange.parameter(lookup, &collect))
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
    if (overflow)
        return false;
    if (count == 1 && at == 0)
    {
        value = defaultValue !is null ? defaultValue : "";
        return true;
    }
    value = stack[0 .. at].idup;
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

A buffer stays borrowed while the exchange sends it, and a send can suspend the handler, so the pool holds as many
buffers as requests run at once: the servlet engine's handler limit is 200 by default (Tomcat's threads.max). With
16 slots, 64 keep-alive connections missed on a third of their requests and each miss allocated a new buffer (816
bytes), most of gs-rest-service's GC traffic. Only buffers actually used are allocated, and idle ones gather in the
lowest slots, which acquire scans first.
+/
private final class BodyPool
{
    private Body[256] slots;

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
