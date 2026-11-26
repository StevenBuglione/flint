module micrometer_histogram_snapshot_test;

import core.memory : GC;
import flint.java.util.concurrent : TimeUnit;
import flint.micrometer.core.instrument.distribution : HistogramSnapshot;

@safe:

@("a snapshot without buckets retains its totals")
unittest
{
    auto snapshot = HistogramSnapshot.empty(2, 5_000_000.0, 3_000_000.0);
    const allocatedBefore = GC.stats().allocatedInCurrentThread;
    assert(snapshot.count() == 2);
    assert(snapshot.total() == 5_000_000.0 && snapshot.total(TimeUnit.MILLISECONDS) == 5.0);
    assert(snapshot.max() == 3_000_000.0 && snapshot.max(TimeUnit.MILLISECONDS) == 3.0);
    assert(snapshot.mean() == 2_500_000.0 && snapshot.mean(TimeUnit.MILLISECONDS) == 2.5);
    assert(snapshot.percentileValues().length == 0 && snapshot.histogramCounts().length == 0);
    assert(GC.stats().allocatedInCurrentThread == allocatedBefore);
    assert(snapshot.toString() == "HistogramSnapshot{count=2, total=5000000.0, mean=2500000.0, max=3000000.0}");
}

@("a zero recording count yields a positive zero mean")
unittest
{
    auto snapshot = HistogramSnapshot.empty(0, -1.0, -0.0);
    assert(snapshot.count() == 0 && snapshot.total() == -1.0);
    assert(1.0 / snapshot.max() == -double.infinity);
    assert(1.0 / snapshot.mean() == double.infinity);
    assert(1.0 / snapshot.mean(TimeUnit.MICROSECONDS) == double.infinity);
    assert(snapshot.toString() == "HistogramSnapshot{count=0, total=-1.0, mean=0.0, max=-0.0}");
}
