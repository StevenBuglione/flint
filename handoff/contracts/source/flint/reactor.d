/// Public API contract; declarations are not runtime implementations.
module flint.reactor;
import flint.arena : Status, Error, Result;
import flint.conc : Context, Deadline;

@safe:
enum Backend
{
    automatic,
    ioUring,
    kqueue,
    iocp
}

struct ReactorOptions
{
    Backend backend = Backend.automatic;
    uint cores = 0;
    uint completionsPerTick = 256;
    uint maxConnectionsPerCore = 8192;
    uint fiberPoolSize = 1024;
    size_t fiberStackBytes = 65536;
}

struct ConnectionId
{
    uint ownerCore;
    uint slot;
    ulong generation;
}

struct TimerId
{
    uint ownerCore;
    uint slot;
    ulong generation;
}

struct ListenOptions
{
    string host = "127.0.0.1";
    ushort port = 8080;
    uint backlog = 1024;
}

struct Completion
{
    ConnectionId connection;
    Status status;
    size_t bytes;
}

alias AcceptFn = void function(ConnectionId) @safe nothrow @nogc;
alias CompletionFn = void function(Completion) @safe nothrow @nogc;
struct Reactor
{
    private ulong id;
    @disable this(this);
    static Result!Reactor create(ReactorOptions options);
    Error listen(ListenOptions options, AcceptFn accept);
    Error run();
    void stop() nothrow @nogc;
    Error post(uint ownerCore, void function() @safe nothrow @nogc task) nothrow @nogc;
    Error close(ConnectionId connection) nothrow @nogc;
    uint currentCore() const nothrow @nogc;
}
