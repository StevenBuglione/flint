module micrometer_meter_provider_test;

import flint.java.lang : IllegalArgumentException, Iterable;
import flint.java.util : ArrayList;
import flint.micrometer.core.instrument : Counter, ImmutableTag, Meter, Tag, Tags;
import flint.micrometer.core.instrument.simple : SimpleMeterRegistry;
import std.exception : assertThrown;

@safe:

private alias Provider = Meter.MeterProvider!Counter;

private struct MeterWrapper
{
    Meter wrapped;
    alias wrapped this;
}

private class MeterFacade
{
    Meter wrapped;
    alias wrapped this;
}

private interface Marker
{
}

private interface SpecializedCounter : Marker, Counter
{
}

private abstract class DerivedCounter : Object, SpecializedCounter
{
}

static assert(!is(Meter.MeterProvider!MeterWrapper));
static assert(!is(Meter.MeterProvider!MeterFacade));
static assert(is(Meter.MeterProvider!SpecializedCounter));
static assert(is(Meter.MeterProvider!DerivedCounter));
static assert(!is(typeof(Provider.init.withTags(Iterable!(const ImmutableTag).init))));

private final class CounterProvider : Provider
{
    private SimpleMeterRegistry registry;

    this(SimpleMeterRegistry registry)
    {
        this.registry = registry;
    }

    override Counter withTags(Iterable!Tag tags)
    {
        return registry.counter("requests", tags);
    }

    mixin Provider.Defaults;
}

private final class RetainingProvider : Provider
{
    Iterable!Tag retained;
    alias withTags = Provider.withTags;

    override Counter withTags(Iterable!Tag tags)
    {
        retained = tags;
        return null;
    }

    mixin Provider.Defaults;
}

@("tag subtype iterables are forwarded lazily without sorting, deduplicating, or copying")
unittest
{
    auto first = new ImmutableTag("zone", "east");
    auto second = new ImmutableTag("method", "POST");
    auto third = new ImmutableTag("zone", "west");
    auto tags = new ArrayList!ImmutableTag;
    tags.add(first);
    tags.add(second);

    auto receiver = new RetainingProvider;
    Provider provider = receiver;
    provider.withTags(tags);
    tags.add(third);

    auto iterator = receiver.retained.iterator();
    assert(iterator.next() is first);
    assert(iterator.next() is second);
    assert(iterator.next() is third);
    assert(!iterator.hasNext());
    iterator.remove();
    assert(tags.size() == 2);

    Tag[] visited;
    receiver.retained.forEach((Tag tag) { visited ~= tag; });
    assert(visited.length == 2 && visited[0] is first && visited[1] is second);

    foreach (tag; receiver.retained)
    {
        assert(tag is first);
        break;
    }

    Iterable!ImmutableTag absent;
    provider.withTags(absent);
    assert(receiver.retained is null);

    receiver.withTags(tags);
    assert(receiver.retained.iterator().next() is first);

    auto exact = Tags.empty();
    provider.withTags(exact);
    assert(receiver.retained is exact);
}

@("meter provider defaults normalize tag pairs before dispatching to the typed provider")
unittest
{
    auto registry = new SimpleMeterRegistry;
    Provider provider = new CounterProvider(registry);
    const Counter tagged = provider.withTag("method", "POST");
    assert(tagged is provider.withTags(Tags.of("method", "POST")));
    assert(tagged is provider.withTags("method", "GET", "method", "POST"));
    assert(tagged !is provider.withTag("method", "GET"));
    assert(provider.withTags() is registry.counter("requests"));
    assertThrown!IllegalArgumentException(provider.withTags("method"));
}
