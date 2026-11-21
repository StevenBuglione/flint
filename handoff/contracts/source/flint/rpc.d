// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.rpc;
import flint.arena : Buffer, Error, RequestArena, Result;
import flint.conc : Context;

@safe:
struct WebSocket
{
    string path;
}

struct Sse
{
    string path;
}

struct GrpcService
{
    string serviceName;
}

enum RpcCode : uint
{
    ok = 0,
    cancelled = 1,
    unknown = 2,
    invalidArgument = 3,
    deadlineExceeded = 4,
    notFound = 5,
    alreadyExists = 6,
    permissionDenied = 7,
    resourceExhausted = 8,
    failedPrecondition = 9,
    aborted = 10,
    outOfRange = 11,
    unimplemented = 12,
    internal = 13,
    unavailable = 14,
    dataLoss = 15,
    unauthenticated = 16
}

struct RpcStatus
{
    RpcCode code;
    Buffer message;
}

struct StreamLimits
{
    size_t maxMessageBytes = 4 * 1024 * 1024;
    uint queuedMessages = 16;
    size_t queuedBytes = 1024 * 1024;
}

struct RpcStream
{
    private ulong slot;
    private ulong generation;
    Error send(Buffer message, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Result!Buffer receive(ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Error finish(RpcStatus status) nothrow @nogc;
    Error cancel() nothrow @nogc;
}

struct WebSocketPeer
{
    private ulong slot;
    private ulong generation;
    Error text(Buffer text, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Error binary(Buffer payload, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Error close(ushort code = 1000, string reason = "") nothrow @nogc;
}

struct SseEvent
{
    string event;
    string id;
    Buffer data;
    uint retryMillis;
}

Error sendEvent(ref RpcStream stream, scope const ref SseEvent event, ref scope RequestArena arena, ref Context context) nothrow @nogc;
Result!Buffer encodeProto(T)(scope const ref T message, ref scope RequestArena arena) nothrow @nogc;
Error decodeProto(T)(scope const(ubyte)[] wire, ref T message, ref scope RequestArena arena) nothrow @nogc;
