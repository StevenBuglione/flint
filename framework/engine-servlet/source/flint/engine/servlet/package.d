/++
Flint's servlet container: `jakarta.servlet` over `flint.engine.web` fiber routes.

It plays the part embedded Tomcat plays under Spring Boot. Each request runs its filter chain and servlet on its
own reactor fiber (ADR-030 section 4), with request bytes copied out of the arena before any application code
runs. It reproduces what Spring Boot 4.2.0 on Tomcat puts on the wire:
- status lines without a reason phrase;
- `Content-Length` for a response that is never committed, and chunked framing for one committed without a length;
- Tomcat's field order;
- an error page forward after `sendError` or an uncaught exception, with the `jakarta.servlet.error.*` request
  attributes Tomcat's `StandardHostValve` sets.

Boot's web server support drives it through `start`, `stop`, `getPort` and `shutDownGracefully`, as
spring-boot-tomcat drives Tomcat.
+/
module flint.engine.servlet;

import flint.arena : Status;
import flint.conc : Context, Deadline;
import flint.engine.aot.any : Any;
import flint.engine.aot.fast : FastDispatch, FastField, FastFilter, FastFilterEffect, FastOutcome;
import flint.engine.servlet.request : DispatchState, RequestHost, RequestState,
    ServletEngineRequest, decimal, methodName;
import flint.engine.servlet.exchange : StatePool, freshState, retire;
import flint.engine.servlet.response : ResponseState, ServletEngineResponse;
import flint.engine.web.fiber : FiberResponse, FiberRoute;
import flint.engine.web.runtime : Server;
import flint.engine.web.types : Request, RequestContext, ServerOptions, ShutdownMode;
import flint.jakarta.servlet : DispatcherType, Filter, FilterChain, FilterConfig,
    FilterRegistration, RequestDispatcher, Servlet, ServletConfig,
    ServletContext, ServletException, ServletRegistration, ServletRequest, ServletRequestWrapper, ServletResponse;
import flint.jakarta.servlet.http : HttpServletRequest, HttpServletResponse;
import flint.java.lang : IllegalArgumentException, IllegalStateException;

@safe:

/// Thrown when the engine cannot start, such as when its port is in use.
class ServletEngineException : Exception
{
    /// The port the engine tried to bind, or 0.
    immutable int port;

    ///
    this(string message, int port = 0, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, file, line);
        this.port = port;
    }
}

/// Listener, context and error-page settings: what Boot's `ServerProperties` and `ErrorPageCustomizer` give
/// Tomcat.
struct ServletEngineOptions
{
    /// `server.address`: the interface to bind.
    string address = "0.0.0.0";
    /// `server.port`; 0 binds an ephemeral port, which `getPort` reports.
    ushort port = 8080;
    /// `server.servlet.context-path`: `""` or a path starting with `/` and not ending with one.
    string contextPath = "";
    /// Error pages by status code.
    string[int] errorPages;
    /// The page for every other error; Boot's `ErrorPageCustomizer` registers `/error`. `null` for none.
    string globalErrorPage = "/error";
    /// `server.shutdown`.
    ShutdownMode shutdown = ShutdownMode.graceful;
    /// Reactor threads serving requests. 0, the default, serves on every CPU the process may run on, up to the
    /// engine's 16, as Tomcat's request thread pool spans the CPUs.
    uint cores = 0;
    /// Idle keep-alive time; Tomcat's default keep-alive timeout is its 60 s connection timeout.
    long keepAliveTimeoutNanos = 60_000_000_000L;
    /// `server.tomcat.max-keep-alive-requests`: requests a persistent connection serves before its response
    /// carries `Connection: close` and it closes, Tomcat's default of 100. 1 disables keep-alive; any value below 1
    /// is unlimited, as Tomcat's `Http11Processor` limits only values above 0. Boot documents 0 as disabling
    /// keep-alive, so Flint Boot's factory passes 1 for a property of 0; this field takes the engine value as is.
    int maxKeepAliveRequests = 100;
    /// Largest request body (the engine caps it at 1 MiB).
    size_t maxBodyBytes = 1_048_576;
    /// Connections each reactor thread holds.
    uint maxConnectionsPerCore = 4096;
    /// `server.flint.max-handlers`: requests handled at once across the reactor threads, Tomcat's
    /// `server.tomcat.threads.max` and its default of 200. A request past it waits on its connection, in arrival
    /// order, until a handler finishes, as Tomcat's executor queues it. 0 gives each reactor thread one handler
    /// per connection slot, up to 1,088 (the sizing before this setting).
    uint maxHandlers = 200;
    /// Flint's per-endpoint fast path (docs/spring/phase1/fast-path.md): `flint.engine.servlet.fast.serveFast`,
    /// set only by the customizer Flint AOT generates when an endpoint qualifies; null serves every request
    /// generically and links none of the fast path.
    FastOffer fastOffer;
    /// Flint's error-page shortcut (`ErrorPageShortcut`), set only by the customizer Flint AOT generates when
    /// startup proves stock error handling; null forwards every error generically.
    ErrorPageShortcut errorPageShortcut;
}

/++
Flint addition: a startup-proved replacement for the error-page forward (docs/spring/phase1/fast-path.md). Flint
AOT installs one only after it has proved that forwarding to the error page would run stock Spring error handling
(Boot's error controller, attributes and converter) through an empty ERROR filter chain. It then writes the same
response without the second dispatch.

The engine calls `install` once when it starts, after its filters are mapped, and `writeErrorPage` at each forward:
after the `jakarta.servlet.error.*` attributes are set and the response is reset for the page, and before the
ERROR dispatch.
+/
interface ErrorPageShortcut
{
    /// Whether to serve this engine's forwards, decided once at start, when the filter chain is final, so the
    /// proof can inspect it (`ServletEngine.filtersFor`). False leaves every forward generic.
    bool install(ServletEngine engine);

    /// Write the response that forwarding to `page` for `status` would write, and return true. Or return false
    /// having changed nothing, and the engine forwards. A throw ends the forward as a failing error page does.
    bool writeErrorPage(HttpServletRequest request, HttpServletResponse response, int status, string page);
}

/// The fast path's offer of one exchange to a servlet (`flint.engine.servlet.fast.serveFast`).
alias FastOffer = FastOutcome function(ServletEngine engine, FastDispatch dispatch, ref scope Request request,
        ref scope RequestContext context, FiberResponse transport, out ServletEngineRequest servletRequest,
        out ServletEngineResponse servletResponse, out Exception failure) @safe;

/// The reactor threads for `cores`: `cores` itself, or for 0 the CPUs this process may run on (on Linux, its
/// affinity mask), at most the engine's 16.
private uint reactorThreads(uint cores) nothrow @nogc
{
    import std.parallelism : totalCPUs;

    enum engineLimit = 16; // flint.engine.web's ceiling on reactor workers
    if (cores != 0)
        return cores;
    const count = totalCPUs;
    return count == 0 ? 1 : count > engineLimit ? engineLimit : count;
}

@("ServletEngineOptions.cores 0 serves on every available CPU, at most 16")
unittest
{
    assert(ServletEngineOptions.init.cores == 0);
    const all = reactorThreads(0);
    assert(all >= 1 && all <= 16);
    assert(reactorThreads(3) == 3);
}

/// A servlet container on Flint's HTTP engine.
final class ServletEngine : RequestHost
{
    private ServletEngineOptions options;
    private EngineContext servletContext;
    private ServletEntry[] servlets;
    private FilterEntry[] filters;
    private ServletEntry defaultServlet;
    private FilterEntry[] chainOrder;
    // The servlet's fast path (fast-path.md), offered each request before capture; null when the servlet has
    // none, or a mapped filter does not state its effect (S4), since a filter sees the objects of every request.
    private FastDispatch fastDispatch;
    // The proved error-page shortcut, once `install` accepted this engine; null forwards generically.
    private ErrorPageShortcut errorShortcut;
    // The mapped filters' effects on fast-path requests, in chain order, and their fields (fast-path.md S4).
    package(flint.engine.servlet) FastFilterEffect[] fastFilterEffects;
    package(flint.engine.servlet) FastField[] fastFilterFields;
    private Server server;
    private bool started;
    private bool stopped;
    private ushort boundPort;

    ///
    this(ServletEngineOptions options = ServletEngineOptions.init)
    {
        if (options.contextPath.length != 0 && (options.contextPath[0] != '/' || options.contextPath[$ - 1] == '/'))
            throw new IllegalArgumentException("ContextPath must start with '/' and must not end with '/'");
        this.options = options;
        servletContext = new EngineContext(options.contextPath, this);
    }

    /// The servlet context shared by every servlet and filter.
    ServletContext getServletContext()
    {
        return servletContext;
    }

    /// Register a servlet and map it, as `ServletRegistrationBean` does through `ServletContext.addServlet`. The
    /// engine maps one servlet, at `/` (the default servlet, which `DispatcherServlet` is under Boot) or `/*`.
    void addServlet(string name, Servlet servlet, string[] mappings = ["/"])
    {
        auto registration = registerServlet(name, servlet);
        if (registration is null)
            throw new IllegalStateException("a servlet named '" ~ name ~ "' is already registered");
        const conflicts = registration.addMapping(mappings);
        if (conflicts.length != 0)
            throw new IllegalStateException("a servlet is already mapped at " ~ conflicts[0]);
    }

    /// Register a filter and map it to `urlPatterns`, as `FilterRegistrationBean` does through
    /// `ServletContext.addFilter` (`REQUEST` dispatches and `isMatchAfter` false by default).
    void addFilter(string name, Filter filter, string[] urlPatterns = ["/*"],
            DispatcherType[] dispatcherTypes = [DispatcherType.REQUEST])
    {
        auto registration = registerFilter(name, filter);
        if (registration is null)
            throw new IllegalStateException("a filter named '" ~ name ~ "' is already registered");
        registration.addMappingForUrlPatterns(dispatcherTypes, false, urlPatterns);
    }

    /// `ServletContext.addServlet`: null for a duplicate name; `IllegalStateException` once started.
    package(flint.engine.servlet) ServletRegistration.Dynamic registerServlet(string name, Servlet servlet)
    {
        if (started)
            throw new IllegalStateException("servlets are registered before the engine starts");
        if (servlet is null || name.length == 0)
            throw new IllegalArgumentException("Servlet name and servlet must not be empty");
        foreach (existing; servlets)
            if (existing.name == name)
                return null;
        auto entry = new ServletEntry(this, name, servlet);
        servlets ~= entry;
        return entry;
    }

    /// `ServletContext.addFilter`: null for a duplicate name; `IllegalStateException` once started.
    package(flint.engine.servlet) FilterRegistration.Dynamic registerFilter(string name, Filter filter)
    {
        if (started)
            throw new IllegalStateException("filters are registered before the engine starts");
        if (filter is null || name.length == 0)
            throw new IllegalArgumentException("Filter name and filter must not be empty");
        foreach (existing; filters)
            if (existing.name == name)
                return null;
        auto entry = new FilterEntry(this, name, filter);
        filters ~= entry;
        return entry;
    }

    /// Initialize the servlets and filters, bind the port and begin serving. Returns once requests are admitted.
    void start()
    {
        if (started)
            return;
        initializeComponents();

        ServerOptions serverOptions;
        serverOptions.address = options.address;
        serverOptions.port = options.port;
        serverOptions.cores = reactorThreads(options.cores);
        // One pool of exchange storage per worker, touched only by that worker (coordination/notes/exchange-pool.md).
        responsePools = new StatePool!ResponseState[serverOptions.cores];
        requestPools = new StatePool!RequestState[serverOptions.cores];
        serverOptions.http2 = false;
        serverOptions.idleTimeoutNanos = options.keepAliveTimeoutNanos;
        serverOptions.maxKeepAliveRequests = options.maxKeepAliveRequests;
        serverOptions.maxBodyBytes = options.maxBodyBytes;
        serverOptions.maxConnectionsPerCore = options.maxConnectionsPerCore;
        serverOptions.maxHandlers = options.maxHandlers;
        serverOptions.shutdown = options.shutdown;
        const opened = server.start(serverOptions);
        if (opened.code != Status.ok)
            throw new ServletEngineException(opened.code == Status.conflict || opened.code == Status.unavailable
                    ? "Port " ~ decimal(
                        options.port) ~ " is already in use" : "Unable to start the servlet engine: " ~ opened.message,
                    options.port);
        const routed = server.routeFiber(FiberRoute(&serve));
        if (routed.code != Status.ok)
            throw new ServletEngineException("Unable to route requests: " ~ routed.message, options.port);
        boundPort = server.listenPort();
        Context context;
        const admitted = server.poll(context);
        if (admitted.code != Status.ok)
            throw new ServletEngineException("Unable to admit requests: " ~ admitted.message, options.port);
        started = true;
    }

    /// Pick the servlet mapped at `/` or `/*`, order the filter chain and initialize every servlet and filter.
    private void initializeComponents()
    {
        foreach (entry; servlets)
            if (entry.mappings.length != 0)
                defaultServlet = entry;
        if (defaultServlet is null)
            throw new IllegalStateException("no servlet is mapped at / or /*");
        // Tomcat's addFilterMapBefore and addFilterMap: mappings declared with isMatchAfter false run first, each
        // group in declaration order.
        foreach (after; [false, true])
            foreach (entry; filters)
                if (entry.mapped && entry.after == after)
                    chainOrder ~= entry;
        foreach (entry; servlets)
            entry.servlet.init(new EngineConfig(entry.name, servletContext, entry.parameters));
        foreach (entry; filters)
            entry.filter.init(new EngineFilterConfig(entry.name, servletContext, entry.parameters));
        if (options.fastOffer !is null && fastFiltersStated())
            if (auto candidate = cast(FastDispatch) defaultServlet.servlet)
                if (candidate.hasFastPath())
                    fastDispatch = candidate;
        if (options.errorPageShortcut !is null && options.errorPageShortcut.install(this))
            errorShortcut = options.errorPageShortcut;
    }

    /// Flint addition: the filters a dispatch of `type` to `servletPath` runs, in chain order, once the engine has
    /// started; for proofs such as an `ErrorPageShortcut`'s.
    Filter[] filtersFor(DispatcherType type, string servletPath)
    {
        Filter[] found;
        foreach (entry; chainOrder)
            if (entry.applies(servletPath, type, defaultServlet.name))
                found ~= entry.filter;
        return found;
    }

    /// Flint addition: the servlet every dispatch ends at, the one mapped at `/` (null before the engine starts);
    /// for proofs such as an `ErrorPageShortcut`'s.
    Servlet defaultServletInstance()
    {
        return defaultServlet is null ? null : defaultServlet.servlet;
    }

    /++
    Whether every mapped filter states its effect on a fast-path request (fast-path.md S4): it is mapped at `/*` for
    `REQUEST` dispatches, so it runs for every request the fast path could answer, and it implements `FastFilter`.
    The effects are kept in chain order. This engine has no secure connector, so the effect is the plain one.
    +/
    private bool fastFiltersStated()
    {
        FastFilterEffect[] effects;
        foreach (entry; chainOrder)
        {
            auto fast = cast(FastFilter) entry.filter;
            if (fast is null || entry.urlPatterns != ["/*"] || entry.servletNames.length != 0)
                return false;
            bool request = entry.dispatcherTypes.length == 0;
            foreach (type; entry.dispatcherTypes)
                request = request || type == DispatcherType.REQUEST;
            FastFilterEffect effect;
            if (!request || !fast.fastEffect(false, effect))
                return false;
            effects ~= effect;
        }
        fastFilterEffects = effects;
        foreach (ref effect; effects)
            fastFilterFields ~= effect.fields;
        return true;
    }

    /// Stop at once: admitted requests are cancelled. Idempotent.
    void stop()
    {
        if (!started || stopped)
            return;
        stopped = true;
        server.shutdown(nanosFromNow(5_000_000_000L));
        destroyComponents();
    }

    /// The bound port, which resolves a configured port of 0; -1 before `start`.
    int getPort()
    {
        return started ? boundPort : -1;
    }

    /// Refuse new connections and let admitted requests finish within `timeoutNanos`, then stop. Returns true
    /// when every request finished (Boot's `GracefulShutdownResult.IDLE`) and false when some were still active
    /// and were cancelled (`REQUESTS_ACTIVE`).
    bool shutDownGracefully(long timeoutNanos)
    {
        if (!started || stopped)
            return true;
        stopped = true;
        const drained = server.drain(nanosFromNow(timeoutNanos));
        destroyComponents();
        return drained.code == Status.ok;
    }

    // RequestHost

    /// `HttpServletRequest.context`.
    ServletContext context()
    {
        return servletContext;
    }

    /// `HttpServletRequest.localAddress`.
    string localAddress()
    {
        return options.address;
    }

    /// `HttpServletRequest.localPort`.
    int localPort()
    {
        return boundPort;
    }

    /// `HttpServletRequest.dispatcher`.
    RequestDispatcher dispatcher(string path)
    {
        return new EngineDispatcher(this, path);
    }

    // Request processing

    /// The fiber route: one exchange from request bytes to the finished response.
    private void serve(ref scope Request request, ref scope RequestContext context, FiberResponse transport)
    {
        if (fastDispatch !is null)
        {
            // Called through the option, so a server without the fast path never references serveFast.
            ServletEngineRequest fastRequest;
            ServletEngineResponse fastResponse;
            Exception fastFailure;
            final switch (options.fastOffer(this, fastDispatch, request, context, transport, fastRequest,
                    fastResponse, fastFailure))
            {
            case FastOutcome.declined:
                // Nothing ran (serveFast asserts it); storage a broken dispatcher took anyway is returned, so its
                // façades stop working, and the generic path takes its own.
                closeExchange(fastRequest, fastResponse, context.worker);
                break;
            case FastOutcome.written:
                closeExchange(fastRequest, fastResponse, context.worker);
                return;
            case FastOutcome.materialized:
                finishExchange(fastRequest, fastResponse, fastFailure);
                closeExchange(fastRequest, fastResponse, context.worker);
                return;
            }
        }
        auto servletRequest = capture(request, context);
        auto servletResponse = openResponse(transport, context.worker);
        if (!withinContext(servletRequest.getRequestURI()))
        {
            // Tomcat's Mapper finds no context for the URI: the host's ErrorReportValve answers 404.
            hostErrorReport(servletResponse, 404, "Not Found");
            servletResponse.complete();
            closeExchange(servletRequest, servletResponse, context.worker);
            return;
        }
        Exception failure;
        try
            new Chain(this, DispatcherType.REQUEST).doFilter(servletRequest, servletResponse);
        catch (Exception e)
            failure = e;
        finishExchange(servletRequest, servletResponse, failure);
        // The storage is returned whenever finishExchange returns, after a handler's exception too (the error page
        // has answered it), and the exchange's objects then throw. Only an exception out of finishExchange itself
        // (the client gone mid-response) skips this: the storage then goes to the GC, never reused.
        closeExchange(servletRequest, servletResponse, context.worker);
    }

    // Per-worker pools of exchange storage, indexed by `RequestContext.worker` (flint.engine.servlet.exchange).
    private StatePool!ResponseState[] responsePools;
    private StatePool!RequestState[] requestPools;

    // A response for a new exchange on `worker`, with storage from that worker's pool.
    private ServletEngineResponse openResponse(FiberResponse transport, uint worker)
    {
        ulong generation;
        auto state = worker < responsePools.length
            ? responsePools[worker].take(generation) : freshState!ResponseState(generation);
        return new ServletEngineResponse(transport, state, generation);
    }

    // The end of a completed exchange: everything the exchange wrote has been copied to the transport (engine-web
    // takes `scope` bytes and copies them), so its storage goes back to the worker's pool and its objects stop
    // working (owner decision (a)).
    private void closeExchange(ServletEngineRequest request, ServletEngineResponse response, uint worker)
    {
        ulong generation;
        if (request !is null)
        {
            auto state = request.pooledState(generation);
            if (worker < requestPools.length)
                requestPools[worker].release(state, generation);
            else
                retire(state, generation);
        }
        if (response !is null)
        {
            auto state = response.pooledState(generation);
            if (worker < responsePools.length)
                responsePools[worker].release(state, generation);
            else
                retire(state, generation);
        }
    }

    /// For tests: the free response states the worker's pool holds.
    package(flint.engine.servlet) size_t pooledResponses(uint worker) const pure nothrow @nogc
    {
        return worker < responsePools.length ? responsePools[worker].held() : 0;
    }

    /// Tomcat's valves after the filter chain: an uncaught exception or `sendError` goes to the error page, then
    /// the response completes.
    private void finishExchange(ServletEngineRequest servletRequest, ServletEngineResponse servletResponse,
            Exception failure)
    {
        if (failure !is null)
            throwable(servletRequest, servletResponse, failure);
        else if (servletResponse.isError())
            status(servletRequest, servletResponse);
        servletResponse.complete();
    }

    /// The fast path's materialization: the request the generic path captures, and a new response.
    package(flint.engine.servlet) ServletEngineRequest captureRequest(ref scope Request request,
            ref scope RequestContext context)
    {
        return capture(request, context);
    }

    /// ditto
    package(flint.engine.servlet) ServletEngineResponse newResponse(FiberResponse transport, uint worker)
    {
        return openResponse(transport, worker);
    }

    /// `server.servlet.context-path`, for the fast path's own context check.
    package(flint.engine.servlet) string contextPathOf() const pure nothrow @nogc
    {
        return options.contextPath;
    }

    /// Whether `uri` is inside this engine's one context (Tomcat maps `/ctx` itself, and `/ctx/...`).
    private bool withinContext(string uri) const pure nothrow @nogc
    {
        const path = options.contextPath;
        if (path.length == 0)
            return true;
        if (uri.length < path.length || uri[0 .. path.length] != path)
            return false;
        return uri.length == path.length || uri[path.length] == '/';
    }

    /// Tomcat's `ErrorReportValve` as Spring Boot configures it (no report, no server info), for a request no
    /// context serves: an HTML page naming the status, in English.
    private static void hostErrorReport(ServletEngineResponse response, int code, string reason)
    {
        import flint.java.util : Locale;

        response.setStatus(code);
        response.setContentType("text/html");
        response.setCharacterEncoding("utf-8");
        response.setLocale(Locale.forLanguageTag("en"));
        const title = "HTTP Status " ~ decimal(code) ~ " \u2013 " ~ reason;
        const page = `<!doctype html><html lang="en"><head><title>` ~ title ~ `</title><style type="text/css">`
            ~ "body {font-family:Tahoma,Arial,sans-serif;} h1, h2, h3, b {color:white;background-color:#525D76;} "
            ~ "h1 {font-size:22px;} h2 {font-size:16px;} h3 {font-size:14px;} p {font-size:12px;} "
            ~ "a {color:black;} .line {height:1px;background-color:#525D76;border:none;}</style></head><body><h1>"
            ~ title ~ "</h1></body></html>";
        response.getOutputStream().write(cast(const(ubyte)[]) page);
    }

    /// Copy the request out of the arena: two GC allocations (the request and one copy of its head and body)
    /// however many fields it has.
    private ServletEngineRequest capture(ref scope Request request, ref scope RequestContext context)
    {
        import flint.arena : Buffer, Result;

        size_t total;
        size_t[3] sizes;
        const pathBuffer = request.path(), queryBuffer = request.query(), bodyBuffer = request.body();
        sizes[0] = pathBuffer.ok() ? pathBuffer.value.length() : 0;
        sizes[1] = queryBuffer.ok() ? queryBuffer.value.length() : 0;
        sizes[2] = bodyBuffer.ok() ? bodyBuffer.value.length() : 0;
        total = sizes[0] + sizes[1];
        const count = request.fieldCount();
        size_t[64] small = void; // the lengths of up to 32 fields, without an allocation
        size_t[] lengths = count * 2 <= small.length ? small[0 .. count * 2] : new size_t[count * 2];
        foreach (index; 0 .. count)
        {
            request.visitField(index, context.arena, (scope const(char)[] name,
                    scope const(ubyte)[] value) @safe nothrow @nogc {
                lengths[index * 2] = name.length;
                lengths[index * 2 + 1] = value.length;
            });
            total += lengths[index * 2] + lengths[index * 2 + 1];
        }
        total += sizes[2];
        // The text is gathered on the stack for a usual request head and frozen once for the request to keep.
        char[4096] stackText = void;
        char[] text = total <= stackText.length ? stackText[0 .. total] : new char[total];
        size_t used;
        void copy(Result!Buffer buffer, size_t size)
        {
            if (size == 0)
                return;
            auto destination = text[used .. used + size];
            context.arena.read(buffer.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
                destination[] = cast(const(char)[]) bytes;
            });
            used += size;
        }

        copy(pathBuffer, sizes[0]);
        copy(queryBuffer, sizes[1]);
        foreach (index; 0 .. count)
        {
            auto name = text[used .. used + lengths[index * 2]];
            auto value = text[used + lengths[index * 2] .. used + lengths[index * 2] + lengths[index * 2 + 1]];
            // dfmt off
            request.visitField(index, context.arena,
                    (scope const(char)[] n, scope const(ubyte)[] v) @safe nothrow @nogc {
                name[] = n;
                value[] = cast(const(char)[]) v;
            });
            // dfmt on
            used += name.length + value.length;
        }
        copy(bodyBuffer, sizes[2]);
        immutable frozen = text.idup;
        const path = frozen[0 .. sizes[0]];
        // A request without '?' has no query string; "?" alone is an empty one.
        string query = sizes[1] != 0 ? frozen[sizes[0] .. sizes[0] + sizes[1]] : null;
        ulong generation;
        auto state = context.worker < requestPools.length
            ? requestPools[context.worker].take(generation) : freshState!RequestState(generation);
        auto captured = new ServletEngineRequest(this, methodName(request.method()), path, query,
                request.protocolMinor() == 0 ? "HTTP/1.0" : "HTTP/1.1", options.contextPath, null,
                null, null, context.requestId, state, generation);
        auto fields = captured.fieldStorage(count * 2);
        auto names = fields[0 .. count], values = fields[count .. $];
        size_t at = sizes[0] + sizes[1];
        foreach (index; 0 .. count)
        {
            names[index] = frozen[at .. at + lengths[index * 2]];
            at += lengths[index * 2];
            values[index] = frozen[at .. at + lengths[index * 2 + 1]];
            at += lengths[index * 2 + 1];
        }
        immutable(ubyte)[] content = sizes[2] != 0 ? cast(immutable(ubyte)[]) frozen[at .. $] : null;
        captured.setCaptured(names, values, content);
        return captured;
    }

    /// Tomcat's `StandardWrapperValve.exception` and `StandardHostValve.throwable`: an uncaught exception becomes a
    /// 500 and, unless the response is committed, a forward to the error page.
    private void throwable(ServletEngineRequest request, ServletEngineResponse response, Exception failure)
    {
        Throwable cause = failure;
        // StandardHostValve unwraps ServletException to its root cause.
        while (auto wrapped = cast(ServletException) cause)
        {
            if (wrapped.getRootCause() is null)
                break;
            cause = wrapped.getRootCause();
        }
        if (response.isWireCommitted())
            return;
        response.setErrorStatus(500);
        const page = errorPage(500);
        if (page is null)
            return;
        request.setAttribute(RequestDispatcher.ERROR_EXCEPTION, Any.of(cast(Object) cause));
        request.setAttribute(RequestDispatcher.ERROR_EXCEPTION_TYPE, Any.of(typeid(cause).name));
        forwardToErrorPage(request, response, page, 500, messageOf(cause).idup);
    }

    /// Tomcat's `StandardHostValve.status`: after `sendError`, forward to the status's error page.
    private void status(ServletEngineRequest request, ServletEngineResponse response)
    {
        const code = response.getStatus();
        const page = errorPage(code);
        if (page is null || response.isWireCommitted())
            return;
        forwardToErrorPage(request, response, page, code, response.getErrorMessage());
    }

    private string errorPage(int code)
    {
        if (auto page = code in options.errorPages)
            return *page;
        return options.globalErrorPage;
    }

    private void forwardToErrorPage(ServletEngineRequest request, ServletEngineResponse response,
            string page, int code, string message)
    {
        request.setAttribute(RequestDispatcher.ERROR_STATUS_CODE, Any.of(code));
        request.setAttribute(RequestDispatcher.ERROR_MESSAGE, Any.of(message is null ? "" : message));
        request.setAttribute(RequestDispatcher.ERROR_REQUEST_URI, Any.of(request.getRequestURI()));
        if (request.getQueryString() !is null)
            request.setAttribute(RequestDispatcher.ERROR_QUERY_STRING, Any.of(request.getQueryString()));
        request.setAttribute(RequestDispatcher.ERROR_METHOD, Any.of(request.getMethod()));
        request.setAttribute(RequestDispatcher.ERROR_SERVLET_NAME, Any.of(defaultServlet.name));
        response.prepareErrorPage();
        if (errorShortcut !is null)
        {
            bool written;
            try
                written = errorShortcut.writeErrorPage(request, response, code, page);
            catch (Exception)
                return; // as a failing error page: the status with what was written
            if (written)
                return;
        }
        auto previous = request.redirect(page, null, DispatcherType.ERROR);
        scope (exit)
            request.restore(previous);
        try
            new Chain(this, DispatcherType.ERROR).doFilter(request, response);
        catch (Exception)
        {
            // Tomcat logs a failing error page and sends the status with what the page wrote.
        }
    }

    private void destroyComponents()
    {
        foreach (entry; filters)
            entry.filter.destroy();
        foreach (entry; servlets)
            entry.servlet.destroy();
    }
}

private long nanosFromNow(long nanos)
{
    return Deadline.afterMillis(nanos / 1_000_000).monotonicNanoseconds;
}

/// What `Registration` keeps for a servlet or a filter.
private abstract class EntryBase
{
    protected ServletEngine engine;
    string name;
    string[string] parameters;

    this(ServletEngine engine, string name) pure nothrow @nogc
    {
        this.engine = engine;
        this.name = name;
    }

    string getName()
    {
        return name;
    }

    bool setInitParameter(string parameter, string value)
    {
        if (parameter.length == 0 || value is null)
            throw new IllegalArgumentException("Init parameter name and value must not be null");
        if (engine.started)
            throw new IllegalStateException("the engine has started");
        if ((parameter in parameters) !is null)
            return false;
        parameters[parameter] = value;
        return true;
    }

    string getInitParameter(string parameter)
    {
        if (auto value = parameter in parameters)
            return *value;
        return null;
    }

    /// The engine does not run servlets asynchronously; the setting is recorded and has no effect.
    void setAsyncSupported(bool)
    {
    }
}

/// A servlet added through `ServletContext.addServlet`.
private final class ServletEntry : EntryBase, ServletRegistration.Dynamic
{
    Servlet servlet;
    string[] mappings;
    private string runAsRole;

    this(ServletEngine engine, string name, Servlet servlet) pure nothrow @nogc
    {
        super(engine, name);
        this.servlet = servlet;
    }

    override string getName()
    {
        return name;
    }

    override bool setInitParameter(string parameter, string value)
    {
        return super.setInitParameter(parameter, value);
    }

    override string getInitParameter(string parameter)
    {
        return super.getInitParameter(parameter);
    }

    override void setAsyncSupported(bool supported)
    {
        super.setAsyncSupported(supported);
    }

    string getClassName()
    {
        return typeid(servlet).name;
    }

    string[] addMapping(string[] urlPatterns...)
    {
        if (engine.started)
            throw new IllegalStateException("the engine has started");
        string[] conflicts;
        foreach (pattern; urlPatterns)
        {
            if (pattern != "/" && pattern != "/*")
                throw new IllegalArgumentException("the servlet engine maps a servlet at / or /* only, not " ~ pattern);
            bool taken;
            foreach (other; engine.servlets)
                taken = taken || (other !is this && other.mappings.length != 0);
            if (taken)
                conflicts ~= pattern;
            else
                mappings ~= pattern;
        }
        return conflicts;
    }

    string[] getMappings()
    {
        return mappings.dup;
    }

    string getRunAsRole()
    {
        return runAsRole;
    }

    /// Every servlet is initialized when the engine starts.
    void setLoadOnStartup(int)
    {
    }

    void setRunAsRole(string roleName)
    {
        runAsRole = roleName;
    }
}

/// A filter added through `ServletContext.addFilter`.
private final class FilterEntry : EntryBase, FilterRegistration.Dynamic
{
    Filter filter;
    string[] urlPatterns;
    string[] servletNames;
    DispatcherType[] dispatcherTypes;
    bool after;
    bool mapped;

    this(ServletEngine engine, string name, Filter filter) pure nothrow @nogc
    {
        super(engine, name);
        this.filter = filter;
    }

    override string getName()
    {
        return name;
    }

    override bool setInitParameter(string parameter, string value)
    {
        return super.setInitParameter(parameter, value);
    }

    override string getInitParameter(string parameter)
    {
        return super.getInitParameter(parameter);
    }

    override void setAsyncSupported(bool supported)
    {
        super.setAsyncSupported(supported);
    }

    string getClassName()
    {
        return typeid(filter).name;
    }

    void addMappingForServletNames(DispatcherType[] types, bool isMatchAfter, string[] names...)
    {
        map(types, isMatchAfter);
        servletNames ~= names;
    }

    string[] getServletNameMappings()
    {
        return servletNames.dup;
    }

    void addMappingForUrlPatterns(DispatcherType[] types, bool isMatchAfter, string[] patterns...)
    {
        map(types, isMatchAfter);
        urlPatterns ~= patterns;
    }

    string[] getUrlPatternMappings()
    {
        return urlPatterns.dup;
    }

    private void map(DispatcherType[] types, bool isMatchAfter)
    {
        if (engine.started)
            throw new IllegalStateException("the engine has started");
        foreach (type; types.length != 0 ? types : [DispatcherType.REQUEST])
        {
            bool known;
            foreach (existing; dispatcherTypes)
                known = known || existing == type;
            if (!known)
                dispatcherTypes ~= type;
        }
        after = isMatchAfter;
        mapped = true;
    }

    bool applies(string servletPath, DispatcherType type, string servletName) const
    {
        bool typed;
        foreach (candidate; dispatcherTypes)
            typed = typed || candidate == type;
        if (!typed)
            return false;
        foreach (candidate; servletNames)
            if (candidate == servletName || candidate == "*")
                return true;
        foreach (pattern; urlPatterns)
            if (urlPatternMatches(pattern, servletPath))
                return true;
        return false;
    }
}

/// Servlet URL-pattern matching: exact, path prefix (`/api/*`), extension (`*.json`) and `/*`.
private bool urlPatternMatches(string pattern, string servletPath) pure nothrow @nogc
{
    if (pattern == "/*" || pattern == servletPath)
        return true;
    if (pattern.length >= 2 && pattern[$ - 2 .. $] == "/*")
    {
        const prefix = pattern[0 .. $ - 2];
        return servletPath.length >= prefix.length && servletPath[0 .. prefix.length] == prefix
            && (servletPath.length == prefix.length || servletPath[prefix.length] == '/');
    }
    if (pattern.length > 2 && pattern[0 .. 2] == "*.")
    {
        const extension = pattern[1 .. $];
        return servletPath.length >= extension.length
            && servletPath[servletPath.length - extension.length .. $] == extension;
    }
    return false;
}

/// The engine's own request under any `ServletRequestWrapper`s a filter put around it (Tomcat's
/// `ApplicationDispatcher` walks the wrappers the same way); null for a request from elsewhere.
private ServletEngineRequest engineRequest(ServletRequest request)
{
    for (auto current = request; current !is null;)
    {
        if (auto own = cast(ServletEngineRequest) current)
            return own;
        auto wrapper = cast(ServletRequestWrapper) current;
        if (wrapper is null)
            return null;
        current = wrapper.getRequest();
    }
    return null;
}

/// Tomcat's `ApplicationFilterChain`: the matching filters in order, then the servlet. Matching reads the
/// engine's request, so a wrapper a filter passes on does not change which filters run.
private final class Chain : FilterChain
{
    private ServletEngine engine;
    private DispatcherType type;
    private size_t next;

    this(ServletEngine engine, DispatcherType type) pure nothrow @nogc
    {
        this.engine = engine;
        this.type = type;
    }

    void doFilter(ServletRequest request, ServletResponse response)
    {
        auto http = engineRequest(request);
        const servletPath = http is null ? "/" : http.getServletPath();
        while (next < engine.chainOrder.length)
        {
            auto entry = engine.chainOrder[next++];
            if (entry.applies(servletPath, type, engine.defaultServlet.name))
            {
                entry.filter.doFilter(request, response, this);
                return;
            }
        }
        engine.defaultServlet.servlet.service(request, response);
    }
}

/// `RequestDispatcher` for a path in this engine: forwards and includes run the servlet in the same exchange.
private final class EngineDispatcher : RequestDispatcher
{
    private ServletEngine engine;
    private string path;

    this(ServletEngine engine, string path) pure nothrow @nogc
    {
        this.engine = engine;
        this.path = path;
    }

    void forward(ServletRequest request, ServletResponse response)
    {
        auto http = engineRequest(request);
        if (http is null)
            throw new ServletException("the servlet engine forwards its own requests only");
        if (response.isCommitted())
            throw new IllegalStateException("Cannot forward after response has been committed");
        response.resetBuffer();
        string target = path, query = null;
        foreach (index, c; path)
        {
            if (c == '?')
            {
                target = path[0 .. index];
                query = path[index + 1 .. $];
                break;
            }
        }
        http.setAttribute(RequestDispatcher.FORWARD_REQUEST_URI, Any.of(http.getRequestURI()));
        http.setAttribute(RequestDispatcher.FORWARD_CONTEXT_PATH, Any.of(http.getContextPath()));
        http.setAttribute(RequestDispatcher.FORWARD_SERVLET_PATH, Any.of(http.getServletPath()));
        if (http.getQueryString() !is null)
            http.setAttribute(RequestDispatcher.FORWARD_QUERY_STRING, Any.of(http.getQueryString()));
        auto previous = http.redirect(target, query, DispatcherType.FORWARD);
        scope (exit)
            http.restore(previous);
        new Chain(engine, DispatcherType.FORWARD).doFilter(request, response);
    }

    void include(ServletRequest request, ServletResponse response)
    {
        auto http = engineRequest(request);
        if (http is null)
            throw new ServletException("the servlet engine includes its own requests only");
        http.setAttribute(RequestDispatcher.INCLUDE_REQUEST_URI, Any.of(http.getContextPath() ~ path));
        http.setAttribute(RequestDispatcher.INCLUDE_CONTEXT_PATH, Any.of(http.getContextPath()));
        http.setAttribute(RequestDispatcher.INCLUDE_SERVLET_PATH, Any.of(path));
        scope (exit)
        {
            http.removeAttribute(RequestDispatcher.INCLUDE_REQUEST_URI);
            http.removeAttribute(RequestDispatcher.INCLUDE_CONTEXT_PATH);
            http.removeAttribute(RequestDispatcher.INCLUDE_SERVLET_PATH);
        }
        new Chain(engine, DispatcherType.INCLUDE).doFilter(request, response);
    }
}

private final class EngineContext : ServletContext
{
    private string contextPath;
    private ServletEngine engine;
    private Any[string] attributes;

    this(string contextPath, ServletEngine engine) pure nothrow @nogc
    {
        this.contextPath = contextPath;
        this.engine = engine;
    }

    ServletRegistration.Dynamic addServlet(string servletName, Servlet servlet)
    {
        return engine.registerServlet(servletName, servlet);
    }

    FilterRegistration.Dynamic addFilter(string filterName, Filter filter)
    {
        return engine.registerFilter(filterName, filter);
    }

    string getContextPath()
    {
        return contextPath;
    }

    // The attributes are shared by every reactor thread, as Tomcat's ApplicationContext keeps them in a
    // ConcurrentHashMap.
    Any getAttribute(string name)
    {
        synchronized (this)
        {
            if (auto value = name in attributes)
                return *value;
        }
        return Any.init;
    }

    void setAttribute(string name, Any object)
    {
        synchronized (this)
        {
            if (object.isNull())
                attributes.remove(name);
            else
                attributes[name] = object;
        }
    }

    string getServerInfo()
    {
        return "Flint servlet engine";
    }

    string getMimeType(string file)
    {
        static immutable string[2][] types = [
            [".html", "text/html"], [".htm", "text/html"], [".css", "text/css"],
            [".js", "text/javascript"], [".json", "application/json"], [".txt", "text/plain"],
            [".png", "image/png"], [".jpg", "image/jpeg"], [".jpeg", "image/jpeg"],
            [".gif", "image/gif"], [".svg", "image/svg+xml"], [".ico", "image/x-icon"],
            [".xml", "application/xml"], [".pdf", "application/pdf"]
        ];
        foreach (pair; types)
            if (file.length >= pair[0].length && file[$ - pair[0].length .. $] == pair[0])
                return pair[1];
        return null;
    }

    int getMajorVersion()
    {
        return 6;
    }

    int getMinorVersion()
    {
        return 1;
    }
}

private final class EngineConfig : ServletConfig
{
    private string name;
    private ServletContext context;
    private const(string[string]) parameters;

    this(string name, ServletContext context, const(string[string]) parameters) pure nothrow @nogc
    {
        this.name = name;
        this.context = context;
        this.parameters = parameters;
    }

    string getServletName()
    {
        return name;
    }

    ServletContext getServletContext()
    {
        return context;
    }

    string getInitParameter(string parameter)
    {
        if (auto value = parameter in parameters)
            return *value;
        return null;
    }

    string[] getInitParameterNames()
    {
        return parameters.keys;
    }
}

private final class EngineFilterConfig : FilterConfig
{
    private string name;
    private ServletContext context;
    private const(string[string]) parameters;

    this(string name, ServletContext context, const(string[string]) parameters) pure nothrow @nogc
    {
        this.name = name;
        this.context = context;
        this.parameters = parameters;
    }

    string getFilterName()
    {
        return name;
    }

    ServletContext getServletContext()
    {
        return context;
    }

    string getInitParameter(string parameter)
    {
        if (auto value = parameter in parameters)
            return *value;
        return null;
    }

    string[] getInitParameterNames()
    {
        return parameters.keys;
    }
}

// Java's `Throwable.getMessage()`: a Flint exception's `getMessage`, which a subclass may build on demand, and
// druntime's message for any other D throwable (as boot's DefaultErrorAttributes reads it, dad69381).
private const(char)[] messageOf(Throwable error)
{
    import flint.java.lang : AssertionError, RuntimeException;

    if (auto runtime = cast(RuntimeException) error)
        return runtime.getMessage();
    if (auto assertion = cast(AssertionError) error)
        return assertion.getMessage();
    return error.message();
}
