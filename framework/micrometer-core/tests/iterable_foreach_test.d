module micrometer_iterable_foreach_test;

import flint.java.lang : Iterable, NullPointerException;
import flint.java.util : ArrayList, Iterator;
import flint.java.util.function_.consumer : Consumer;
import flint.micrometer.core.instrument : Counter, ImmutableTag, Measurement, Meter, Tag, Tags;
import flint.micrometer.core.instrument.noop : NoopCounter;
import flint.micrometer.core.instrument.simple : SimpleMeterRegistry;
import std.exception : assertThrown;
import std.typecons : Nullable;

@safe:

private alias Provider = Meter.MeterProvider!Counter;

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

/// A Tag-subtype iterable without the Defaults mixin: it records every way the view could reach it.
private final class TouchedTags : Iterable!ImmutableTag
{
    private ArrayList!ImmutableTag items;
    size_t touches;

    this(ArrayList!ImmutableTag items)
    {
        this.items = items;
    }

    override Iterator!ImmutableTag iterator()
    {
        ++touches;
        return items.iterator();
    }

    override void forEach(void delegate(ImmutableTag) @safe action)
    {
        ++touches;
        foreach (item; items)
            action(item);
    }

    override void forEach(Consumer!ImmutableTag action)
    {
        ++touches;
        foreach (item; items)
            action.accept(item);
    }

    override int opApply(scope int delegate(ImmutableTag) @safe dg)
    {
        ++touches;
        return items.opApply(dg);
    }
}

private void assertRejectsNull(T)(Iterable!T iterable)
{
    assertThrown!NullPointerException(iterable.forEach(cast(void delegate(T) @safe) null));
    assertThrown!NullPointerException(iterable.forEach(cast(Consumer!T) null));
}

private Measurement[] iterated(Iterable!Measurement measurements)
{
    Measurement[] samples;
    for (auto it = measurements.iterator(); it.hasNext();)
        samples ~= it.next();
    return samples;
}

private void assertConsumerVisitsInOrder(Iterable!Measurement measurements)
{
    Measurement[] visited;
    measurements.forEach(Consumer!Measurement.of((Measurement sample) { visited ~= sample; }));
    assert(visited == iterated(measurements));
}

@("Tags.empty() forEach rejects a null action like Java's default")
unittest
{
    assertRejectsNull!Tag(Tags.empty());
    size_t calls;
    Tags.empty().forEach(Consumer!Tag.of((Tag) { ++calls; }));
    assert(calls == 0);
}

@("Tags forEach(Consumer) visits the normalized tags in order")
unittest
{
    auto tags = Tags.of("zone", "east", "method", "POST", "a", "1");
    string[] keys;
    tags.forEach(Consumer!Tag.of((Tag tag) { keys ~= tag.getKey(); }));
    assert(keys == ["a", "method", "zone"]);
    assertRejectsNull!Tag(tags);
}

@("empty, single and meter measurement iterables reject a null action and visit in order")
unittest
{
    auto id = new Meter.Id("noop", Tags.empty(), Nullable!string(), Nullable!string(), Meter.Type.COUNTER);
    auto empty = new NoopCounter(id).measure();
    assert(empty.isEmpty());
    assertRejectsNull!Measurement(empty);
    assertConsumerVisitsInOrder(empty);

    auto registry = new SimpleMeterRegistry;
    auto single = registry.counter("work").measure();
    assert(iterated(single).length == 1);
    assertRejectsNull!Measurement(single);
    assertConsumerVisitsInOrder(single);

    auto timed = registry.timer("latency").measure();
    assert(iterated(timed).length == 3);
    assertRejectsNull!Measurement(timed);
    assertConsumerVisitsInOrder(timed);

    auto summarized = registry.summary("size").measure();
    assert(iterated(summarized).length > 1);
    assertRejectsNull!Measurement(summarized);
    assertConsumerVisitsInOrder(summarized);
}

@("a forwarded Tag-subtype view rejects a null action before reaching its source")
unittest
{
    auto first = new ImmutableTag("zone", "east");
    auto second = new ImmutableTag("method", "POST");
    auto items = new ArrayList!ImmutableTag;
    items.add(first);
    items.add(second);
    auto source = new TouchedTags(items);

    auto receiver = new RetainingProvider;
    Provider provider = receiver;
    provider.withTags(source);
    auto view = receiver.retained;

    assertRejectsNull!Tag(view);
    assert(source.touches == 0);

    Tag[] visited;
    view.forEach(Consumer!Tag.of((Tag tag) { visited ~= tag; }));
    assert(visited.length == 2 && visited[0] is first && visited[1] is second);
}
