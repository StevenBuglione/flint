// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.actuator;
import flint.arena : Buffer, Error, RequestArena, Result;
import flint.conc : Context;
import flint.web : Server;

@safe:
enum HealthStatus : ubyte
{
    up,
    down,
    unknown
}

struct Health
{
    HealthStatus status;
    string component;
}

alias HealthProbe = Health delegate() @safe nothrow @nogc;
struct Counter
{
    private uint id;
}

struct Histogram
{
    private uint id;
}

struct TraceContext
{
    ubyte[16] traceId;
    ubyte[8] spanId;
    ubyte flags;
}

struct Span
{
    private ulong slot;
    private ulong generation;
    Error finish(long monotonicNanos, bool failed) nothrow @nogc;
}

struct ActuatorOptions
{
    string pathPrefix = "/actuator";
    uint maxMetricSeries = 4096;
    uint maxSpansQueued = 8192;
    uint maxBatchSpans = 256;
    string otlpEndpoint;
    long exportIntervalNanos = 5_000_000_000L;
}

struct Registry
{
    private ulong slot;
    private ulong generation;
    Error open(ActuatorOptions options);
    Result!Counter counter(string name, string help);
    Result!Histogram histogram(string name, scope const(double)[] bounds);
    void add(Counter counter, ulong delta = 1) nothrow @nogc;
    void record(Histogram histogram, double value) nothrow @nogc;
    Error health(string name, HealthProbe probe);
    Result!Buffer scrape(ref scope RequestArena arena) nothrow @nogc;
    Result!Span beginSpan(string name, TraceContext parent, long monotonicNanos) nothrow @nogc;
    Error exportBatch(ref Context context) nothrow @nogc;
    Error attach(ref Server server);
    Error close(ref Context context) nothrow @nogc;
}
