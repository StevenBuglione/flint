module app;

import core.stdc.stdio : fputc, stdout;
import flint.java.time : Duration;
import flint.java.util.concurrent : TimeUnit;
import flint.java.util.concurrent.callable : Callable;
import flint.java.util.function_ : Supplier;
import flint.micrometer.core.instrument : Clock, MockClock, Tags, Timer;
import flint.micrometer.core.instrument.distribution : CountAtBucket, DistributionStatisticConfig,
    Histogram, NoopHistogram, TimeWindowMax, ValueAtPercentile;
import flint.micrometer.core.instrument.simple : SimpleMeterRegistry;
import flint.micrometer.core.instrument.util : TimeUtils;

@safe:

private alias RegionCallable = Callable!string;
private alias RegionSupplier = Supplier!string;

private final class Region : RegionCallable, RegionSupplier
{
    private const string value;

    this(string region)
    {
        value = region;
    }

    override string call()
    {
        return value;
    }

    override string get()
    {
        return value;
    }
}

private bool verifyWrappers(Timer timer, RegionCallable callable, RegionSupplier supplier, string region)
{
    auto wrappedCallable = timer.wrap(callable);
    auto wrappedSupplier = timer.wrap(supplier);
    auto wrappedDelegate = timer.wrap(() => region);
    return timer.count() == 3 && wrappedCallable.call() == region && wrappedSupplier.get() == region
        && wrappedDelegate() == region && timer.count() == 6;
}

private bool verifyHistogramValues()
{
    auto bucket = new CountAtBucket(2_500_000.0, 3.0);
    auto percentile = new ValueAtPercentile(0.95, 2_500_000.0);
    return bucket.bucket(TimeUnit.MILLISECONDS) == 2.5
        && percentile.value(TimeUnit.MILLISECONDS) == 2.5 && TimeUtils.convert(bucket.bucket(),
                TimeUnit.NANOSECONDS, TimeUnit.MILLISECONDS) == 2.5
        && TimeUtils.millisToUnit(percentile.value(TimeUnit.MILLISECONDS),
                TimeUnit.MICROSECONDS) == 2_500 && bucket.toString() == "(3.0 at 2500000.0)"
        && percentile.toString() == "(2500000.0 at 95.0%)" && verifyEmptySnapshot();
}

private bool verifyEmptySnapshot()
{
    Histogram histogram = NoopHistogram.INSTANCE;
    histogram.recordLong(7);
    histogram.recordDouble(1.5);
    histogram.close();
    auto snapshot = histogram.takeSnapshot(2, 5_000_000.0, 3_000_000.0);
    return snapshot.mean(TimeUnit.MILLISECONDS) == 2.5 && snapshot.max(TimeUnit.MILLISECONDS) == 3.0
        && snapshot.percentileValues().length == 0 && snapshot.histogramCounts().length == 0
        && snapshot.toString() == "HistogramSnapshot{count=2, total=5000000.0, mean=2500000.0, max=3000000.0}";
}

private bool verifyDistribution(MockClock clock)
{
    auto config = DistributionStatisticConfig.builder().percentiles(0.95)
        .expiry(Duration.ofMillis(2)).bufferLength(2).build().merge(DistributionStatisticConfig.DEFAULT);
    auto percentiles = config.getPercentiles();
    if (percentiles.isNull() || percentiles.get().length != 1 || percentiles.get()[0] != 0.95
            || config.isPercentileHistogram().get())
        return false;
    auto maximum = new TimeWindowMax(clock, config);
    maximum.record(3.0);
    clock.add(3, TimeUnit.MILLISECONDS);
    if (maximum.poll() != 3.0)
        return false;
    clock.add(1, TimeUnit.MILLISECONDS);
    return maximum.poll() == 0.0 && verifyHistogramValues();
}

private bool verifySample(Timer timer, MockClock clock)
{
    auto sample = Timer.start(clock);
    clock.add(250, TimeUnit.MILLISECONDS);
    const elapsed = sample.stop(timer);
    if (elapsed != 250_000_000 || timer.count() != 1 || timer.totalTime(TimeUnit.SECONDS) != 0.25
            || timer.max(TimeUnit.SECONDS) != 0.25)
        return false;
    auto snapshot = timer.takeSnapshot();
    return snapshot.count() == 1 && snapshot.total() == elapsed && snapshot.max() == elapsed;
}

private bool verifySummary(SimpleMeterRegistry registry)
{
    auto summary = registry.summary("response.size");
    summary.record(5.25);
    summary.record(1.25);
    auto snapshot = summary.takeSnapshot();
    return summary.mean() == 3.25 && snapshot.count() == 2 && snapshot.total() == 6.5 && snapshot.max() == 5.25;
}

void main(string[] args)
{
    string region = args.length > 1 ? args[1] : "west";
    auto tags = Tags.of("region", region, "method", "GET").and("method", "POST");
    auto registry = new SimpleMeterRegistry;
    if (registry.config().clock() !is Clock.SYSTEM)
        return;
    auto timer = Timer.builder("request.duration").tags(tags).register(registry);
    auto clock = new MockClock;
    if (!verifySample(timer, clock))
        return;
    auto action = new Region(region);
    RegionCallable callable = action;
    if (timer.recordCallable(callable) != region || timer.count() != 2)
        return;
    RegionSupplier supplier = action;
    if (timer.record(supplier) != region || timer.count() != 3)
        return;
    if (!verifyWrappers(timer, callable, supplier, region))
        return;
    if (!verifyDistribution(clock))
        return;
    if (!verifySummary(registry))
        return;
    foreach (character; tags.toString())
        fputc(character, stdout);
    fputc('\n', stdout);
}
