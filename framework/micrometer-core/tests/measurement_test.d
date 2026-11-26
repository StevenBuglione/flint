module micrometer_measurement_test;

import flint.java.util.function_ : DoubleSupplier, Supplier;
import flint.micrometer.core.instrument : Measurement, Statistic;
import flint.micrometer.core.instrument.simple : SimpleMeterRegistry;

@safe:

@("measurement samples its source each time and keeps its statistic")
unittest
{
    double value = 1.25;
    auto direct = new Measurement(DoubleSupplier.of(() => value), Statistic.VALUE);
    auto boxed = new Measurement(Supplier!double.of(() => value), Statistic.MAX);
    auto callback = new Measurement(() => value, Statistic.TOTAL);
    assert(direct.getValue() == 1.25);
    assert(boxed.getValue() == 1.25);
    assert(callback.getValue() == 1.25);
    value = 5.5;
    assert(direct.getValue() == 5.5);
    assert(boxed.getValue() == 5.5);
    assert(direct.getStatistic() == Statistic.VALUE);
    assert(boxed.getStatistic() == Statistic.MAX);
    assert(direct.toString() == "Measurement{statistic='VALUE', value=5.5}");
}

@("counter measurement follows later increments")
unittest
{
    auto registry = new SimpleMeterRegistry;
    auto counter = registry.counter("work");
    auto readings = counter.measure();
    auto samples = readings.iterator();
    assert(samples.hasNext());
    auto sample = samples.next();
    assert(!samples.hasNext());
    assert(readings.iterator().next() is sample);
    assert(sample.getStatistic() == Statistic.COUNT);
    assert(sample.getValue() == 0);
    counter.increment(0.5);
    counter.increment();
    assert(sample.getValue() == 1.5);
}
