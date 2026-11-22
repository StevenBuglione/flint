// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.web;
import flint.arena : Buffer, Error, RequestArena, Result;
import flint.conc : Context;

@safe:
struct RestController
{
    string path;
}

struct RequestMapping
{
    string path;
}

struct Get
{
    string path;
}

struct Post
{
    string path;
}

struct Put
{
    string path;
}

struct Delete
{
    string path;
}

struct PathVariable
{
    string name;
}

struct QueryParam
{
    string name;
    bool required = false;
}

struct RequestBody
{
}

struct ControllerAdvice
{
}

struct ApiVersion
{
    uint major;
}

struct WorkerController
{
}

enum Method : ubyte
{
    get,
    post,
    put,
    patch,
    delete_,
    head,
    options
}

struct ServerOptions
{
    string address = "127.0.0.1";
    ushort port = 8080;
    uint cores = 1;
    uint maxConnectionsPerCore = 4096;
    uint maxStreamsPerConnection = 100;
    size_t maxHeaderBytes = 16384;
    size_t maxBodyBytes = 1048576;
    size_t writeQueueBytes = 262144;
    long headerTimeoutNanos = 5_000_000_000L;
    long idleTimeoutNanos = 30_000_000_000L;
    bool http2 = true;
}

struct RequestContext
{
    RequestArena arena;
    Context cancellation;
    ulong requestId;
}

struct Request
{
    private ulong slot;
    private ulong generation;
    Method method() const nothrow @nogc;
    Result!Buffer path() const nothrow @nogc;
    Result!Buffer header(scope const(char)[] name) const nothrow @nogc;
    Result!Buffer body() const nothrow @nogc;
}

struct Response
{
    ushort status = 200;
    string contentType = "application/json";
    Buffer body;
}

alias Handler = Result!Response delegate(ref Request request, ref RequestContext context) @safe nothrow @nogc;
struct Server
{
    private ulong slot;
    private ulong generation;
    Error start(ServerOptions options);
    Error route(Method method, string path, Handler handler);
    Error poll(ref Context context) nothrow @nogc;
    Error shutdown(long deadlineNanos) nothrow @nogc;
}

Error registerController(C)(ref Server server, ref C controller);
int runApplication(App)(ref App app, ServerOptions options = ServerOptions.init);
