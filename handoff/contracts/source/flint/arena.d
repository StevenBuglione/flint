/// Public API contract; declarations are not runtime implementations.
module flint.arena;

@safe:
enum Status : int
{
    ok,
    invalidArgument,
    outOfMemory,
    cancelled,
    timedOut,
    notFound,
    conflict,
    ioError,
    unavailable,
    unsupported,
    permissionDenied,
    resourceExhausted
}

struct Error
{
    Status code;
    string message;
    size_t offset = size_t.max;
}

struct Result(T)
{
    T value;
    Error error;
    bool ok() const pure nothrow @nogc
    {
        return error.code == Status.ok;
    }
}
/// Opaque identity: caller may copy handles but cannot fabricate a valid one.
struct Buffer
{
    private ulong owner;
    private ulong epoch;
    private size_t start;
    private size_t count;
    private this(ulong owner, ulong epoch, size_t start, size_t count) nothrow @nogc;
    size_t length() const pure nothrow @nogc;
}

struct Text
{
    Buffer bytes;
}

struct ArenaStats
{
    size_t capacity;
    size_t used;
    size_t peak;
    ulong resets;
}
/// Non-copyable, thread-confined, borrows backing storage.
struct RequestArena
{
    private ubyte[] storage;
    private size_t cursor;
    private uint activeBorrows;
    private ulong owner;
    private ulong epoch;
    @disable this(this);
    this(return scope ubyte[] backing) nothrow @nogc;
    Result!Buffer allocate(size_t bytes, size_t alignment = 8) scope nothrow @nogc;
    Result!Buffer copyIn(scope const(ubyte)[] source) scope nothrow @nogc;
    Status read(Buffer handle, scope void delegate(scope const(ubyte)[]) @safe nothrow @nogc visitor) scope nothrow @nogc;
    Status write(Buffer handle, scope void delegate(scope ubyte[]) @safe nothrow @nogc visitor) scope nothrow @nogc;
    Status reset() scope nothrow @nogc;
    ArenaStats stats() const scope nothrow @nogc;
}

struct BufferPoolOptions
{
    size_t blockBytes = 65536;
    size_t blockCount = 256;
}
