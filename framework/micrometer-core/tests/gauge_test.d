module micrometer_gauge_test;

import core.memory : GC;
import flint.micrometer.core.instrument : Gauge, Measurement, Meter, Statistic, Tags;
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
