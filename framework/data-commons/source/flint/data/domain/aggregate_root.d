// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/domain/AbstractAggregateRoot.java
// Copyright 2016-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.domain.aggregate_root;

import flint.data.annotation : Transient;
import flint.data.domain.events : AfterDomainEventPublication, DomainEvents;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : ArrayList, Collection, Collections, List;

@safe:

/// An aggregate root that records the domain events produced by its operations.
class AbstractAggregateRoot(A)
{
    @Transient
    private List!Any recordedEvents;

    /// Register an event for publication and return the event.
    protected T registerEvent(T)(T event)
    {
        static if (is(T == typeof(null)))
            throw new IllegalArgumentException("Domain event must not be null");
        else
        {
            auto value = Any.of(event);
            if (value.isNull())
                throw new IllegalArgumentException("Domain event must not be null");
            events().add(value);
            return event;
        }
    }

    /// Clear the events after publication.
    @AfterDomainEventPublication
    protected void clearDomainEvents()
    {
        if (recordedEvents !is null)
            recordedEvents.clear();
    }

    /// A read-only view of this aggregate's events.
    @DomainEvents
    protected Collection!Any domainEvents()
    {
        return Collections.unmodifiableList(events());
    }

    /// Copy another aggregate's events and return this aggregate.
    protected final A andEventsFrom(A aggregate)
    {
        if (aggregate is null)
            throw new IllegalArgumentException("Aggregate must not be null");
        events().addAll(aggregate.domainEvents());
        return cast(A) this;
    }

    /// Register an event and return this aggregate.
    protected A andEvent(T)(T event)
    {
        registerEvent(event);
        return cast(A) this;
    }

    private List!Any events()
    {
        if (recordedEvents is null)
            recordedEvents = new ArrayList!Any();
        return recordedEvents;
    }
}
