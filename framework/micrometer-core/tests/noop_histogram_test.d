module micrometer_noop_histogram_test;

import core.memory : GC;
import flint.java.lang : AutoCloseable;
import flint.java.util.concurrent : TimeUnit;
import flint.micrometer.core.instrument.distribution : Histogram, HistogramSnapshot, NoopHistogram;

@safe:

private Histogram sharedHistogram() nothrow @nogc
{
    return NoopHistogram.INSTANCE;
}

@("the shared no-op histogram does not allocate or retain recordings")
unittest
{
    const before = GC.stats().allocatedInCurrentThread;
    auto histogram = sharedHistogram();
    assert(histogram !is null && histogram is sharedHistogram());
    histogram.recordLong(40);
    histogram.recordDouble(1.25);
    assert(GC.stats().allocatedInCurrentThread == before);

    AutoCloseable closeable = histogram;
    closeable.close();
    auto snapshot = histogram.takeSnapshot(2, 5_000_000.0, 3_000_000.0);
    assert(snapshot.count() == 2);
    assert(snapshot.total(TimeUnit.MILLISECONDS) == 5.0);
    assert(snapshot.max(TimeUnit.MILLISECONDS) == 3.0);
    assert(snapshot.histogramCounts().length == 0);
    assert(snapshot.percentileValues().length == 0);
}

private final class CustomHistogram : Histogram
{
    mixin Histogram.Defaults;

    private double total = 0.0;

    override void recordLong(long amount) nothrow @nogc
    {
        total += amount;
    }

    override void recordDouble(double amount) nothrow @nogc
    {
        total += amount;
    }

    override HistogramSnapshot takeSnapshot(long count, double amount, double max)
    {
        return HistogramSnapshot.empty(count, amount + total, max);
    }
}

@("a histogram implementing the default close keeps its state")
unittest
{
    Histogram custom = new CustomHistogram;
    custom.recordLong(2);
    custom.recordDouble(2.5);
    custom.close();
    assert(custom.takeSnapshot(2, 1.0, 2.5).total() == 5.5);
}
