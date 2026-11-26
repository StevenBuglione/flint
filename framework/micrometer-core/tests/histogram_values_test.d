module micrometer_histogram_values_test;

import core.memory : GC;
import flint.java.util.concurrent : TimeUnit;
import flint.micrometer.core.instrument.distribution : CountAtBucket, ValueAtPercentile;

@safe:

@("histogram values use Java double equality and hashing")
unittest
{
    auto bucket = new CountAtBucket(double.nan, 0.0);
    auto sameBucket = new CountAtBucket(-double.nan, 0.0);
    auto otherBucket = new CountAtBucket(double.nan, -0.0);
    auto percentile = new ValueAtPercentile(0.95, double.nan);
    auto samePercentile = new ValueAtPercentile(0.95, -double.nan);
    auto positiveZero = new ValueAtPercentile(0.95, 0.0);
    auto negativeZero = new ValueAtPercentile(0.95, -0.0);

    assert(bucket == sameBucket && bucket.hashCode() == sameBucket.hashCode());
    assert(bucket != otherBucket && bucket.hashCode() != otherBucket.hashCode());
    assert(percentile == samePercentile && percentile.hashCode() == samePercentile.hashCode());
    assert(positiveZero != negativeZero && positiveZero.hashCode() != negativeZero.hashCode());
    assert(!bucket.equals(null) && !bucket.equals(percentile));
    assert(!percentile.equals(null) && !percentile.equals(bucket));
}

@("histogram values preserve fractional units without reading allocations")
unittest
{
    auto bucket = new CountAtBucket(2_500_000.0, 3.0);
    auto percentile = new ValueAtPercentile(0.95, 2_500_000.0);
    const allocatedBefore = GC.stats().allocatedInCurrentThread;
    assert(bucket.bucket() == 2_500_000.0 && bucket.count() == 3.0);
    assert(bucket.bucket(TimeUnit.MILLISECONDS) == 2.5);
    assert(percentile.percentile() == 0.95 && percentile.value() == 2_500_000.0);
    assert(percentile.value(TimeUnit.MILLISECONDS) == 2.5);
    assert(GC.stats().allocatedInCurrentThread == allocatedBefore);
    assert(bucket.toString() == "(3.0 at 2500000.0)");
    assert(percentile.toString() == "(2500000.0 at 95.0%)");
}
