module micrometer_counter_builder_test;

import flint.micrometer.core.instrument : Counter, Tags;
import flint.micrometer.core.instrument.simple : SimpleMeterRegistry;
import std.typecons : Nullable;

@safe:

@("counter registration keeps the first description and base unit")
unittest
{
    auto registry = new SimpleMeterRegistry;
    auto metric = Counter.builder("answers").tag("correct", "true")
        .description(Nullable!string("Correct answers")).baseUnit(Nullable!string("answers")).register(registry);
    const duplicate = Counter.builder("answers").tags(Tags.of("correct", "true"))
        .description(Nullable!string("another description")).register(registry);
    assert(metric is duplicate);
    assert(metric is registry.counter("answers", "correct", "true"));
    assert(metric.getId().getDescription().get() == "Correct answers");
    assert(metric.getId().getBaseUnit().get() == "answers");
}

@("editing a counter builder produces a different identity without changing a registered counter")
unittest
{
    auto registry = new SimpleMeterRegistry;
    auto builder = Counter.builder("answers").tags("correct", "true", "grade", "A");
    auto original = builder.register(registry);
    auto updated = builder.tag("correct", "false").register(registry);
    assert(original !is updated);
    assert(original.getId().getTag("correct").get() == "true");
    assert(updated.getId().getTag("correct").get() == "false");
    assert(updated.getId().getTag("grade").get() == "A");
}
