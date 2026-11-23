// Ported from spring-boot v4.2.0: core/spring-boot/src/main/java/org/springframework/boot/availability/ApplicationAvailability.java
// with AvailabilityChangeEvent.java, LivenessState.java, ReadinessState.java and ApplicationAvailabilityBean.java
// from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Java's state enums implement the `AvailabilityState` marker interface, which D enums
// cannot, so the states are two enums and `AvailabilityChangeEvent!S` takes either; `getState(Class<S>)` is
// `getState!S`.

/// `org.springframework.boot.availability`: the application's liveness and readiness.
module flint.boot.availability;

import flint.context : ApplicationEvent, ApplicationEventPublisher, GenericApplicationListener;

@safe:

/// Whether the application's internal state is correct.
enum LivenessState
{
    /// The application is running and its internal state is correct.
    CORRECT,
    /// The application is running but its internal state is broken.
    BROKEN
}

/// Whether the application is ready to accept traffic.
enum ReadinessState
{
    /// The application is ready to receive traffic.
    ACCEPTING_TRAFFIC,
    /// The application is not willing to receive traffic.
    REFUSING_TRAFFIC
}

/// Whether `S` is an availability state.
enum isAvailabilityState(S) = is(S == LivenessState) || is(S == ReadinessState);

/// Published when the application's availability changes.
final class AvailabilityChangeEvent(S) : ApplicationEvent if (isAvailabilityState!S)
{
    private S state;

    /// An event from `source` with the new `state`.
    this(Object source, S state)
    {
        super(source);
        this.state = state;
    }

    /// The new state.
    S getState() const pure nothrow @nogc
    {
        return state;
    }

    /// Publish a change to `state` through `publisher`.
    static void publish(ApplicationEventPublisher publisher, S state)
    {
        publisher.publishEvent(new AvailabilityChangeEvent!S(cast(Object) publisher, state));
    }
}

/// The application's availability, as the latest `AvailabilityChangeEvent`s set it.
interface ApplicationAvailability
{
    /// The liveness state; `BROKEN` until the application has started.
    LivenessState getLivenessState();

    /// The readiness state; `REFUSING_TRAFFIC` until the application is ready.
    ReadinessState getReadinessState();
}

/// Tracks availability from the context's `AvailabilityChangeEvent`s.
class ApplicationAvailabilityBean : ApplicationAvailability, GenericApplicationListener
{
    private LivenessState liveness = LivenessState.BROKEN;
    private ReadinessState readiness = ReadinessState.REFUSING_TRAFFIC;
    private bool livenessSet, readinessSet;

    /// The liveness state.
    LivenessState getLivenessState()
    {
        return liveness;
    }

    /// The readiness state.
    ReadinessState getReadinessState()
    {
        return readiness;
    }

    /// The last state of type `S` published, else `defaultState`.
    S getState(S)(S defaultState) if (isAvailabilityState!S)
    {
        static if (is(S == LivenessState))
            return livenessSet ? liveness : defaultState;
        else
            return readinessSet ? readiness : defaultState;
    }

    /// Accepts availability change events.
    bool supportsEvent(Object event)
    {
        return cast(AvailabilityChangeEvent!LivenessState) event !is null
            || cast(AvailabilityChangeEvent!ReadinessState) event !is null;
    }

    /// Record the new state.
    void dispatchEvent(Object event)
    {
        if (auto change = cast(AvailabilityChangeEvent!LivenessState) event)
        {
            liveness = change.getState();
            livenessSet = true;
        }
        else if (auto change = cast(AvailabilityChangeEvent!ReadinessState) event)
        {
            readiness = change.getState();
            readinessSet = true;
        }
    }

    /// `Ordered.LOWEST_PRECEDENCE`.
    int getListenerOrder()
    {
        return int.max;
    }
}
