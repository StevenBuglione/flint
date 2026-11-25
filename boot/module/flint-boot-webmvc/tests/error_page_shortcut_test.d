// Flint's own tests for the error-page shortcut (Flint addition, docs/spring/phase1/fast-path.md): StockErrorPageShortcut
// against the generic ERROR dispatch through the auto-configured DispatcherServlet. Each case runs twice from scratch,
// as the servlet engine forwards a 404 (the error attributes, the reset buffer, the same request and response), once
// through the shortcut and once through the ERROR dispatch, and the two responses must be identical: status, every
// header in order, the body byte for byte (the timestamp's value aside) and the flush.
module error_page_shortcut_test;

import flint.boot.webmvc.autoconfigure.error : ErrorPageCustomizer, StockErrorPageShortcut;
import flint.context : ApplicationContext;
import flint.engine.aot.any : Any;
import flint.jackson.databind : JsonMapper;
import flint.jakarta.servlet : DispatcherType, RequestDispatcher, ServletRequest, ServletResponse;
import flint.jakarta.servlet.http : HttpServletResponse;
import flint.mock.web : MockHttpServletRequest, MockHttpServletResponse;
import flint.web.bind.annotation : RequestMapping, RestController;
import webmvc_test_support : MvcFixture, controllerRegistry, mvcFixture, webProperties;

@safe:

/// Handlers that set something on the response and then send a 404, as a handler may before an error forward.
@RestController
class ShortcutController
{
    /// A header of its own, then the 404: the forward keeps the header, so the shortcut must too.
    @RequestMapping("/trace404")
    void trace(HttpServletResponse response)
    {
        response.setHeader("X-Trace", "1");
        response.sendError(404);
    }

    /// A Content-Type of its own, then the 404: the shortcut declines.
    @RequestMapping("/typed404")
    void typed(HttpServletResponse response)
    {
        response.setContentType("text/plain");
        response.sendError(404);
    }
}

// The servlet engine's response through an error forward: `sendError` sets the status without committing, and
// `prepareErrorPage` empties the buffer (ServletEngineResponse).
private final class EngineResponse : MockHttpServletResponse
{
    bool error;

    alias sendError = MockHttpServletResponse.sendError;

    override void sendError(int sc, string msg)
    {
        error = true;
        setStatus(sc);
    }
}

// What a forward produced, compared field by field.
private struct Outcome
{
    bool shortcut;
    int status;
    string contentType;
    string[] headers;
    string body;
    bool committed;
}

private JsonMapper stockMapper;

private JsonMapper stockMapperProof(ApplicationContext) @safe
{
    return stockMapper;
}

private JsonMapper otherMapperProof(ApplicationContext) @safe
{
    return JsonMapper.builder().build();
}

private void registry(scope imported!"flint.engine.aot.registry".AotRegistry registry)
{
    controllerRegistry!(ShortcutController, "shortcutController")(registry);
}

// The stock application: Boot's error beans, ErrorPageCustomizer, and the converters over `stockMapper`.
private MvcFixture fixture(string[2][] webEntries = null)
{
    stockMapper = JsonMapper.builder().build();
    Object[string] beans = [
        "errorPageCustomizer": cast(Object) new ErrorPageCustomizer(webProperties(webEntries)),
        "shortcutController": new ShortcutController
    ];
    return mvcFixture(&registry, webEntries, beans, null, null, [stockMapper]);
}

private StockErrorPageShortcut proved(MvcFixture fixture)
{
    auto shortcut = new StockErrorPageShortcut(fixture.context, &stockMapperProof);
    assert(shortcut.prove(fixture.servlet), "the stock application must be proved");
    return shortcut;
}

// One request as the engine runs it: the first dispatch, then ServletEngine.forwardToErrorPage, through the shortcut
// (when `shortcut` is set and accepts) or the ERROR dispatch.
private Outcome forward(MvcFixture fixture, StockErrorPageShortcut shortcut, string method, string uri,
        string query, string[] accepts)
{
    auto request = new MockHttpServletRequest(method, uri);
    if (query.length)
        request.setQueryString(query);
    foreach (accept; accepts)
        request.addHeader("Accept", accept);
    auto response = new EngineResponse;
    fixture.servlet.service(cast(ServletRequest) request, cast(ServletResponse) response);
    assert(response.error, "the first dispatch must send an error");
    const code = response.getStatus();
    request.setAttribute(RequestDispatcher.ERROR_STATUS_CODE, Any.of(code));
    request.setAttribute(RequestDispatcher.ERROR_MESSAGE, Any.of(""));
    request.setAttribute(RequestDispatcher.ERROR_REQUEST_URI, Any.of(request.getRequestURI()));
    if (query.length)
        request.setAttribute(RequestDispatcher.ERROR_QUERY_STRING, Any.of(query));
    request.setAttribute(RequestDispatcher.ERROR_METHOD, Any.of(method));
    request.setAttribute(RequestDispatcher.ERROR_SERVLET_NAME, Any.of("dispatcherServlet"));
    response.resetBuffer();
    Outcome outcome;
    if (shortcut !is null)
        outcome.shortcut = shortcut.writeErrorPage(request, response, code, "/error");
    if (!outcome.shortcut)
    {
        request.setRequestURI("/error");
        request.setDispatcherType(DispatcherType.ERROR);
        fixture.servlet.service(cast(ServletRequest) request, cast(ServletResponse) response);
    }
    outcome.status = response.getStatus();
    outcome.contentType = response.getContentType();
    foreach (name; response.getHeaderNames())
        foreach (value; response.getHeaders(name))
            outcome.headers ~= name ~ ": " ~ value;
    outcome.body = withoutTimestamp(response.getContentAsString());
    outcome.committed = response.isCommitted();
    return outcome;
}

// The body with the timestamp's value emptied: the two runs read the clock at different instants.
private string withoutTimestamp(string body)
{
    import std.string : indexOf;

    enum key = `"timestamp":"`;
    const start = body.indexOf(key);
    if (start < 0)
        return
        body;
    const from = start + key.length;
    const end = body[from .. $].indexOf('"');
    assert(end > 0, "a timestamp value");
    return
    body[0 .. from] ~ body[from + end .. $];
}

// The shortcut's response for `method uri` equals the ERROR dispatch's, and the shortcut wrote it (`writes`) or
// declined.
private void same(MvcFixture fixture, StockErrorPageShortcut shortcut, string method, string uri,
        string query, string[] accepts, bool writes)
{
    const generic = forward(fixture, null, method, uri, query, accepts);
    auto fast = forward(fixture, shortcut, method, uri, query, accepts);
    assert(fast.shortcut == writes, method ~ " " ~ uri ~ (writes ? ": the shortcut must write" : ": must decline"));
    fast.shortcut = false;
    assert(fast == generic, method ~ " " ~ uri ~ ": the shortcut's response differs from the ERROR dispatch's");
}

@("the shortcut writes Boot's JSON 404 exactly as the ERROR dispatch, for every method and Accept key") unittest
{
    auto app = fixture();
    auto shortcut = proved(app);
    foreach (method; ["GET", "POST", "PUT", "DELETE", "PATCH"])
        foreach (accepts; [cast(string[]) null, ["*/*"], ["application/json"]])
            same(app, shortcut, method, "/nope", null, accepts, true);
    const generic = forward(app, null, "GET", "/nope", null, null);
    assert(generic.status == 404 && generic.contentType == "application/json" && generic.committed);
    assert(generic.body == `{"timestamp":"","status":404,"error":"Not Found","path":"/nope"}`, generic.body);
}

@("escaping, encoded and non-ASCII paths and a query string are the ERROR dispatch's") unittest
{
    auto app = fixture();
    auto shortcut = proved(app);
    foreach (uri; [`/a"b\c`, "/x%22y", "/café", "/tab\there", "/deep/er/path.json"])
        same(app, shortcut, "GET", uri, null, null, true);
    same(app, shortcut, "GET", "/nope", "a=1&b=two", ["*/*"], true);
}

@("a header the handler set before its 404 stays on the response, as through the forward") unittest
{
    auto app = fixture();
    auto shortcut = proved(app);
    same(app, shortcut, "GET", "/trace404", null, null, true);
    const outcome = forward(app, shortcut, "GET", "/trace404", null, null);
    assert(outcome.headers.length && outcome.headers[0] == "X-Trace: 1", "the handler's header");
}

@("the shortcut declines what it does not write, and the ERROR dispatch answers") unittest
{
    auto app = fixture();
    auto shortcut = proved(app);
    // Boot's HTML page, a quality value, another type, two Accept fields, and HEAD
    same(app, shortcut, "GET", "/nope", null, ["text/html"], false);
    same(app, shortcut, "GET", "/nope", null, ["application/json;q=0.9"], false);
    same(app, shortcut, "GET", "/nope", null, ["application/xml"], false);
    same(app, shortcut, "GET", "/nope", null, ["*/*", "application/json"], false);
    same(app, shortcut, "HEAD", "/nope", null, null, false);
    // a Content-Type the handler set
    same(app, shortcut, "GET", "/typed404", null, null, false);
}

@("another status or error page is forwarded") unittest
{
    auto app = fixture();
    auto shortcut = proved(app);
    auto request = new MockHttpServletRequest("GET", "/nope");
    request.setAttribute(RequestDispatcher.ERROR_STATUS_CODE, Any.of(405));
    request.setAttribute(RequestDispatcher.ERROR_REQUEST_URI, Any.of("/nope"));
    auto response = new MockHttpServletResponse;
    assert(!shortcut.writeErrorPage(request, response, 405, "/error"));
    assert(!shortcut.writeErrorPage(request, response, 404, "/oops"));
    assert(response.getContentAsString().length == 0 && !response.isCommitted() && response.getStatus() == 200);
}

@("the proof fails without Boot's own mapper in the converter or with request-dependent error attributes") unittest
{
    auto app = fixture();
    assert(!new StockErrorPageShortcut(app.context, &otherMapperProof).prove(app.servlet));
    assert(!new StockErrorPageShortcut(app.context, null).prove(app.servlet));
    auto verbose = fixture([["flint.web.error.include-message", "always"]]);
    assert(!new StockErrorPageShortcut(verbose.context, &stockMapperProof).prove(verbose.servlet));
    auto unproved = new StockErrorPageShortcut(verbose.context, &stockMapperProof);
    assert(!unproved.writeErrorPage(new MockHttpServletRequest("GET", "/nope"),
            new MockHttpServletResponse, 404, "/error"));
}
