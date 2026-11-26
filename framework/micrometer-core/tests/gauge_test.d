module micrometer_gauge_test;

import core.memory : GC;
import flint.java.util.concurrent : TimeUnit;
import flint.micrometer.core.instrument : Gauge, Measurement, Meter, Statistic, Tags, TimeGauge;
import std.typecons : Nullable;

@safe:

private final class SampleGauge : Gauge
{
    private Meter.Id id;
    double amount = 0.0;
    uint reads;

    this()
    {
        id = new Meter.Id("temperature", Tags.empty(), Nullable!string.init, Nullable!string.init, Meter.Type.GAUGE);
    }

    override Meter.Id getId()
    {
        return id;
    }

    override double value()
    {
        reads++;
        return amount;
    }

    mixin Gauge.Defaults;
}

@("a gauge publishes one live value measurement and samples on demand")
unittest
{
    auto sample = new SampleGauge;
    Gauge gauge = sample;
    auto measurements = gauge.measure();
    auto iterator = measurements.iterator();
    assert(sample.reads == 0 && iterator.hasNext());
    auto reading = iterator.next();
    assert(!iterator.hasNext());
    assert(reading.getStatistic() == Statistic.VALUE);
    assert(gauge.getId().getType() == Meter.Type.GAUGE);

    sample.amount = 2.5;
    const before = GC.stats().allocatedInCurrentThread;
    assert(reading.getValue() == 2.5);
    sample.amount = -3.0;
    assert(reading.getValue() == -3.0);
    assert(GC.stats().allocatedInCurrentThread == before && sample.reads == 2);

    uint visits;
    measurements.forEach((Measurement entry) { assert(entry is reading); visits++; });
    assert(visits == 1 && sample.reads == 2);
}

private final class SampleTimeGauge : TimeGauge
{
    alias value = timeGaugeDefaults.value;

    private Meter.Id id;
    private TimeUnit unit = TimeUnit.SECONDS;
    double amount = 0.0;
    uint reads;

    this()
    {
        id = new Meter.Id("latency", Tags.empty(), Nullable!string.init, Nullable!string.init, Meter.Type.GAUGE);
    }

    override Meter.Id getId()
    {
        return id;
    }

    override double value()
    {
        ++reads;
        unit = TimeUnit.MILLISECONDS;
        return amount;
    }

    override TimeUnit baseTimeUnit()
    {
        return unit;
    }

    mixin Gauge.Defaults;
    mixin TimeGauge.Defaults timeGaugeDefaults;
}

@("a time gauge samples before conversion and measures in its base unit")
unittest
{
    auto sample = new SampleTimeGauge;
    TimeGauge gauge = sample;
    auto reading = gauge.measure().iterator().next();
    assert(sample.reads == 0 && reading.getStatistic() == Statistic.VALUE);
    assert(gauge.baseTimeUnit() == TimeUnit.SECONDS);

    sample.amount = 1.5;
    const before = GC.stats().allocatedInCurrentThread;
    assert(gauge.value(TimeUnit.NANOSECONDS) == 1_500_000.0);
    assert(sample.reads == 1 && gauge.baseTimeUnit() == TimeUnit.MILLISECONDS);
    sample.amount = -250.0;
    assert(sample.value(TimeUnit.SECONDS) == -0.25);
    assert(reading.getValue() == -250.0);
    assert(sample.reads == 3 && GC.stats().allocatedInCurrentThread == before);
}
