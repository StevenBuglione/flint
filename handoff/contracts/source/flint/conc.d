/// Public API contract; declarations are not runtime implementations.
module flint.conc;
import flint.arena : Status, Error, Result;

@safe:
struct Deadline
{
    long monotonicNanoseconds;
    static Deadline afterMillis(ulong duration) nothrow @nogc;
    static Deadline none() pure nothrow @nogc;
}

struct Context
{
    private ulong id;
    private Deadline deadlineValue;
    bool cancelled() const nothrow @nogc;
    Deadline deadline() const nothrow @nogc;
    Error check() const nothrow @nogc;
}

struct CancelSource
{
    private ulong id;
    @disable this(this);
    static Result!CancelSource create(Context parent, Deadline deadline) nothrow @nogc;
    Context context() const nothrow @nogc;
    void cancel() nothrow @nogc;
    void close() nothrow @nogc;
}

enum QueueKind
{
    mpsc,
    mpmc
}

struct Channel(T, QueueKind kind = QueueKind.mpsc)
{
    private ulong id;
    @disable this(this);
    static Result!Channel create(size_t capacity) nothrow @nogc;
    Status trySend(T value) nothrow @nogc;
    Result!T tryReceive() nothrow @nogc;
    void close() nothrow @nogc;
}

struct WorkerOptions
{
    uint threads = 4;
    uint queueCapacity = 256;
}

struct WorkTicket
{
    ulong id;
}

alias WorkFn = Error function(scope const(ubyte)[] input, scope ubyte[] output, out size_t written) @safe nothrow @nogc;
struct WorkerPool
{
    private ulong id;
    @disable this(this);
    static Result!WorkerPool create(WorkerOptions options);
    Result!WorkTicket submit(Context context, scope const(ubyte)[] ownedCopy, WorkFn job) nothrow @nogc;
    Error join(WorkTicket ticket, scope ubyte[] output, out size_t written) nothrow @nogc;
    void shutdown() nothrow;
}
