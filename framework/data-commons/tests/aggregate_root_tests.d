// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/domain/AbstractAggregateRootUnitTests.java
// Copyright 2017-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.aggregate_root_tests;

import flint.data.domain : AbstractAggregateRoot;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException, UnsupportedOperationException;
import flint.java.util : Collection, Collections;
import std.exception : assertThrown;

@safe:

private final class SampleAggregate : AbstractAggregateRoot!SampleAggregate
{
    T record(T)(T event)
    {
        return registerEvent(event);
    }

    Collection!Any events()
    {
        return domainEvents();
    }

    void clear()
    {
        clearDomainEvents();
    }

    SampleAggregate merge(SampleAggregate aggregate)
    {
        return andEventsFrom(aggregate);
    }

    SampleAggregate append(Object event)
    {
        return andEvent(event);
    }
}

@("registersEvent")
unittest
{
    auto event = new Object();
    auto aggregate = new SampleAggregate();
    assert(aggregate.record(event) is event);
    assert(aggregate.events().size() == 1);
    assert(aggregate.events().iterator().next().get!Object() is event);
}

@("clearsEvents")
unittest
{
    auto aggregate = new SampleAggregate();
    aggregate.record(new Object());
    assert(!aggregate.events().isEmpty());
    aggregate.clear();
    assert(aggregate.events().isEmpty());
}

@("copiesEventsFromExistingAggregate")
unittest
{
    auto aggregate = new SampleAggregate();
    auto event = new Object();
    aggregate.record(event);

    auto result = new SampleAggregate().merge(aggregate);
    aggregate.clear();
    assert(result.events().size() == 1);
    assert(result.events().iterator().next().get!Object() is event);
}

@("addsEventAndReturnsAggregate")
unittest
{
    auto first = new Object();
    auto second = new Object();
    auto aggregate = new SampleAggregate();
    aggregate.record(first);

    assert(aggregate.append(second) is aggregate);
    auto events = aggregate.events().iterator();
    assert(events.next().get!Object() is first);
    assert(events.next().get!Object() is second);
    assert(!events.hasNext());
}

@("rejectsNullEvent")
unittest
{
    assertThrown!IllegalArgumentException(new SampleAggregate().append(null));
}

@("rejectsNullEventForRegistration")
unittest
{
    assertThrown!IllegalArgumentException(new SampleAggregate().record(null));
}

@("rejectsNullAggregate")
unittest
{
    assertThrown!IllegalArgumentException(new SampleAggregate().merge(null));
}

@("A domain event view stays live and read-only")
unittest
{
    auto aggregate = new SampleAggregate();
    auto view = aggregate.events();
    assert(view.isEmpty());
    aggregate.record(new Object());
    assert(view.size() == 1);
    assertThrown!UnsupportedOperationException(view.clear());
    aggregate.clear();
    assert(view.isEmpty());
}

@("Merging an aggregate with itself copies the original events once")
unittest
{
    auto aggregate = new SampleAggregate();
    assert(aggregate.record(42) == 42);
    assert(aggregate.merge(aggregate) is aggregate);
    auto events = aggregate.events().iterator();
    assert(events.next().get!int() == 42);
    assert(events.next().get!int() == 42);
    assert(!events.hasNext());
}

@("Self-merge uses the aggregate's event accessor")
unittest
{
    static class FilteringAggregate : AbstractAggregateRoot!FilteringAggregate
    {
        override Collection!Any domainEvents() @safe
        {
            return Collections.emptyList!Any();
        }

        void exerciseSelfMerge() @safe
        {
            registerEvent(42);
            andEventsFrom(this);
            assert(super.domainEvents().size() == 1);
        }
    }

    (new FilteringAggregate()).exerciseSelfMerge();
}
