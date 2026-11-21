// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.schedule;
import flint.arena : Error, Result;
import flint.conc : Context;

@safe:
struct Scheduled
{
    string cron;
    long fixedRateNanos;
    long fixedDelayNanos;
    bool concurrent = false;
}

struct Retryable
{
    uint maxAttempts = 3;
    long initialDelayNanos = 100_000_000L;
    long maxDelayNanos = 2_000_000_000L;
}

struct RetryPolicy
{
    uint maxAttempts = 3;
    long initialDelayNanos = 100_000_000L;
    long maxDelayNanos = 2_000_000_000L;
    bool idempotent = false;
}

enum CircuitState : ubyte
{
    closed,
    open,
    halfOpen
}

struct CircuitBreaker
{
    private ulong slot;
    private ulong generation;
    Error open(uint window = 100, uint failurePercent = 50, long openNanos = 30_000_000_000L);
    Result!bool permit(long nowNanos) nothrow @nogc;
    void record(bool success, long nowNanos) nothrow @nogc;
    CircuitState state() const nothrow @nogc;
}

struct RateLimiter
{
    private ulong slot;
    private ulong generation;
    Error open(uint burst, uint tokensPerSecond);
    Result!bool acquire(uint tokens, long nowNanos) nothrow @nogc;
}

alias ScheduledTask = Error delegate(ref Context context) @safe nothrow @nogc;
struct Scheduler
{
    private ulong slot;
    private ulong generation;
    Error open(uint capacity = 1024);
    Result!ulong add(string name, Scheduled schedule, ScheduledTask task);
    Error cancel(ulong taskId) nothrow @nogc;
    Error poll(long utcSeconds, long monotonicNanos) nothrow @nogc;
    Error close(ref Context context) nothrow @nogc;
}

Error withRetry(ref Context context, RetryPolicy policy, scope ScheduledTask operation) nothrow @nogc;
Error registerScheduled(T)(ref Scheduler scheduler, ref T component);
