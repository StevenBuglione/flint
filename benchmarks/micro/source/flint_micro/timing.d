/// Independent monotonic trial timing with verified batches.
module flint_micro.timing;

import core.time : MonoTime;

@safe:

/// The production release procedure retains this many observations per series.
enum trialCount = 21;
/// Every production trial runs batches for at least 100 ms.
enum minimumNanoseconds = 100_000_000L;

/// The number of verified individual operations and their consumed result.
struct BatchResult
{
    /// Completed operations of the measured workload.
    ulong count;
    /// Sum of verified outputs observed by the caller.
    ulong checksum;
}

/// A monomorphic workload invocation with a fixed batch size.
alias Batch = BatchResult delegate(uint operations) @safe nothrow @nogc;

/// A measured interval and the exact operations it covers.
struct Trial
{
    /// Positive elapsed time from a monotonic high-resolution clock.
    long nanoseconds;
    /// Verified count and checksum accumulated over complete batches.
    BatchResult result;
}

/// Warm the selected workload and then observe a complete independent trial.
Trial timeTrial(scope Batch work, uint batchSize, bool smoke) nothrow @nogc
{
    const warmed = work(batchSize);
    if (!warmed.count || !warmed.checksum)
        return Trial.init;
    Trial trial;
    const started = MonoTime.currTime;
    do
    {
        const batch = work(batchSize);
        if (batch.count != warmed.count || batch.checksum != warmed.checksum)
            return Trial.init;
        trial.result.count += batch.count;
        trial.result.checksum += batch.checksum;
        trial.nanoseconds = (MonoTime.currTime - started).total!"nsecs";
    }
    while (!smoke && trial.nanoseconds < minimumNanoseconds);
    return trial;
}
