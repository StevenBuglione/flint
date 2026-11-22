// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.http;
import flint.arena : Buffer, Error, RequestArena, Result;
import flint.conc : Context;

@safe:
struct HttpExchange
{
    string baseUrl;
}

struct GetExchange
{
    string path;
}

struct PostExchange
{
    string path;
}

struct HeaderParam
{
    string name;
}

enum HttpMethod : ubyte
{
    get,
    post,
    put,
    patch,
    delete_,
    head,
    options
}

struct Header
{
    string name;
    string value;
}

struct ClientOptions
{
    uint maxConnections = 64;
    uint maxConnectionsPerOrigin = 16;
    size_t maxResponseBytes = 8 * 1024 * 1024;
    long connectTimeoutNanos = 5_000_000_000L;
    bool followRedirects = false;
    bool verifyPeer = true;
}

struct HttpRequest
{
    HttpMethod method = HttpMethod.get;
    string url;
    Header[] headers;
    Buffer body;
}

struct HttpResponse
{
    ushort status;
    Buffer headers;
    Buffer body;
}

alias ChunkConsumer = Error delegate(scope const(ubyte)[] chunk) @safe nothrow @nogc;
struct HttpClient
{
    private ulong slot;
    private ulong generation;
    Error open(ClientOptions options);
    Result!HttpResponse send(scope const ref HttpRequest request, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Result!ushort stream(scope const ref HttpRequest request, ref scope RequestArena arena,
            ref Context context, scope ChunkConsumer consume) nothrow @nogc;
    Error close() nothrow @nogc;
}

Client bindHttpClient(Client)(ref HttpClient transport);
