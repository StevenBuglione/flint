module micrometer_meter_equivalence_test;

import flint.engine.aot.any : Any;
import flint.java.lang : Iterable, NullPointerException;
import flint.micrometer.core.instrument : AbstractMeter, Measurement, Meter, Tag, Tags;
import flint.micrometer.core.instrument.simple : SimpleMeterRegistry;
import flint.micrometer.core.instrument.util : MeterEquivalence;
import std.exception : assertThrown;
import std.typecons : Nullable;

@safe:

private final class ProbeMeter : AbstractMeter
{
    this(Meter.Id id)
    {
        super(id);
    }

    override Iterable!Measurement measure()
    {
        return null;
    }
}

@("meter equality and hashing use the registered name and tags")
unittest
{
    auto id = new Meter.Id("requests", Tags.of("method", "POST"), Nullable!string.init,
            Nullable!string.init, Meter.Type.OTHER);
    auto original = new ProbeMeter(id);
    auto equivalent = new ProbeMeter(id.withBaseUnit(Nullable!string("requests")));
    auto differentName = new ProbeMeter(id.withName("responses"));
    auto differentTags = new ProbeMeter(id.withTag(Tag.of("method", "GET")));

    assert(original.getId() is id);
    assert(original.equals(equivalent) && original == equivalent);
    assert(!original.equals(differentName) && !original.equals(differentTags));
    assert(!original.equals(null) && !original.equals(new Object));
    auto registry = new SimpleMeterRegistry;
    Meter meter = registry.counter("requests", "method", "POST");
    assert(original.equals(cast(Object) meter));
    assert(MeterEquivalence.equals(original, Any.of(meter)));
    assert(!MeterEquivalence.equals(original, Any.of(17)));
    assert(MeterEquivalence.hashCode(original) == id.hashCode());
    assert(original.hashCode() == equivalent.hashCode());
    assert(original.toHash() == equivalent.toHash());
}

@("meter equivalence checks null operands and compares identical references before reading ids")
unittest
{
    auto missingId = new ProbeMeter(null);
    assert(MeterEquivalence.equals(missingId, Any.of(missingId)));
    assert(!MeterEquivalence.equals(null, Any.init));
    assert(!MeterEquivalence.equals(null, Any.of(missingId)));
    assert(!MeterEquivalence.equals(missingId, Any.init));
    assertThrown!NullPointerException(MeterEquivalence.equals(missingId, Any.of(new ProbeMeter(null))));
    assertThrown!NullPointerException(MeterEquivalence.hashCode(null));
    assertThrown!NullPointerException(missingId.hashCode());
}
