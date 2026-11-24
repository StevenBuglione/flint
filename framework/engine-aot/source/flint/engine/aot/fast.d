/++
The per-endpoint fast path's contract between the servlet container, the dispatcher and Flint AOT's generated code
(docs/spring/phase1/fast-path.md).

The container offers each request to its servlet as a `FastExchange` before it builds any servlet object. A
servlet that implements `FastDispatch` either declines, and the request takes the generic path untouched, or
answers it. Everything the exchange holds is borrowed for the one call: arena bytes never reach user code (ADR-030
section 4), and a value a handler sees is copied to the GC first.

A generated `FastInvoker` reads only the arguments its handler declares, through `FastArguments`, then calls the
handler. It returns `false` only before the handler ran, so a declined request is served generically exactly
once.
+/
module flint.engine.aot.fast;

import flint.engine.aot.any : Any;

@safe:

/// What the container does after `FastDispatch.dispatchFast`.
enum FastOutcome
{
    /// Nothing ran and nothing was sent: serve the request on the generic path.
    declined,
    /// The response is complete.
    written,
    /// The exchange built the servlet request and response (`FastExchange.materialize`); the container finishes
    /// them as the generic path finishes its own, error page included.
    materialized,
}

/// Visits each decoded value of one query parameter; a value is borrowed for the call.
alias FastValueVisitor = void delegate(scope const(char)[] value) @safe;

/// One response header field the fast path writes, in the order the generic response would hold it.
struct FastField
{
    /// The field name, as the generic path spells it.
    string name;
    /// The value.
    string value;
}

/// Sends a whole response with its fields in order (`FastExchange.respondFields`).
alias FastResponder = void delegate(int status, scope const(FastField)[] fields,
        scope const(ubyte)[] content, bool chunked) @safe;

/++
One request as the container holds it before any servlet object exists. Every slice and delegate is valid only
during `FastDispatch.dispatchFast`.
+/
struct FastExchange
{
    /// The method as a servlet sees it (`"GET"`, `"HEAD"`, ...).
    string method;
    /// The path within the servlet context, still percent-encoded, exactly as received.
    const(char)[] path;
    /// How many `Accept` fields the request has, and the first one's value.
    size_t acceptCount;
    /// ditto
    const(char)[] accept;
    /// How many `Origin` fields the request has: a CORS request (or a same-origin one) takes the generic path when
    /// its handler has a CORS configuration.
    size_t originCount;
    /// Visits every value of query parameter `name`, in order, decoded as the servlet request decodes it. Returns
    /// `false` when the fast path cannot decode the query within its bounds, so the caller declines.
    bool delegate(scope const(char)[] name, scope FastValueVisitor visit) @safe parameter;
    /// Sends a whole response: `status`, one `Content-Type` field (none when `contentType` is null), and
    /// `content`, framed as the servlet response would frame the same bytes written without a flush.
    void delegate(int status, string contentType, scope const(ubyte)[] content) @safe respond;
    /// Sends a whole response with `fields` in order. `chunked`: the generic path commits it with a flush before
    /// the content is complete (`HttpEntityMethodProcessor`), so it goes out with `Transfer-Encoding: chunked`;
    /// otherwise it is framed as `respond` frames it (`Content-Length` when it fits the servlet buffer).
    FastResponder respondFields;
    /// Builds the request and response the generic path would have built (the container's own classes, as
    /// `Object`s for this low-level package); the outcome is then `FastOutcome.materialized`.
    void delegate(out Object request, out Object response) @safe materialize;
}

/// Implemented by a servlet that can answer some requests from a `FastExchange`.
interface FastDispatch
{
    /// Whether any request could be answered; the container asks once, when it starts, and offers nothing if not.
    bool hasFastPath();

    /// Decline, answer, or materialize and leave the rest to the container.
    FastOutcome dispatchFast(ref scope FastExchange exchange);
}

/++
The arguments a generated fast handler reads, with Spring's binding rules. The dispatcher fills it on the stack for
one request, so it is a struct of borrowed delegates rather than an object.
+/
struct FastArguments
{
    /++
    `@RequestParam String` binding (`RequestParamMethodArgumentResolver` and the conversion service): the single
    value, or every value joined with `,`; `name[]` when `name` is absent; `defaultValue` for an absent or empty
    single value. Returns `false` to decline: the parameter is required and missing, or the query is beyond the
    fast path's bounds. The bound value is GC memory: it reaches user code.
    +/
    bool delegate(string name, string defaultValue, bool required, out string value) @safe requestParamString;
}

/++
Generated: resolve the handler's arguments from `arguments`, call the handler and store its return value. Returns
`false` only before the handler ran (fast-path.md, "Declining"); after it ran, it returns `true` or throws what the
handler threw.
+/
alias FastInvoker = bool function(Object bean, ref scope FastArguments arguments, ref Any result) @safe;
