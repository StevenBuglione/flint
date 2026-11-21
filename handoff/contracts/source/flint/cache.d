// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.cache;
import flint.arena : Buffer, Error, RequestArena, Result;
import flint.conc : Context;

@safe:
struct Cacheable
{
    string cache;
}

struct CacheEvict
{
    string cache;
    bool allEntries = false;
}

enum CacheBackend : ubyte
{
    local,
    redis
}

struct CacheOptions
{
    CacheBackend backend = CacheBackend.local;
    size_t byteCapacity = 64 * 1024 * 1024;
    uint entryCapacity = 65536;
    uint stripes = 64;
    long defaultTtlNanos = 60_000_000_000L;
    string redisUrl;
}

struct Cache
{
    private ulong slot;
    private ulong generation;
    Error open(CacheOptions options);
    Result!Buffer get(scope const(ubyte)[] key, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Error put(scope const(ubyte)[] key, scope const(ubyte)[] value, long ttlNanos, ref Context context) nothrow @nogc;
    Error evict(scope const(ubyte)[] key, ref Context context) nothrow @nogc;
    Error clear(ref Context context) nothrow @nogc;
    Error close() nothrow @nogc;
}

alias CacheLoader = Result!Buffer delegate(ref scope RequestArena arena, ref Context context) @safe nothrow @nogc;
Result!Buffer getOrLoad(ref Cache cache, scope const(ubyte)[] key, long ttlNanos,
        ref scope RequestArena arena, ref Context context, scope CacheLoader load) nothrow @nogc;
