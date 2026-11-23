// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/availability/
// AvailabilityChangeEventTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Mockito's ApplicationContext is a recording publisher; `@EventListener` on a
// configuration is an `ApplicationListener!(AvailabilityChangeEvent!LivenessState)` added to a context.
// Not ported: createWhenStateIsNullThrowsException (a D enum state cannot be null), getResolvableType and
// getResolvableTypeWhenSubclassedEnum (ResolvableType: `AvailabilityChangeEvent!S` carries `S` statically).
module boot_tests.availability_change_event_test;

import flint.boot.availability : AvailabilityChangeEvent, LivenessState, ReadinessState;
import flint.context : ApplicationEvent, ApplicationEventPublisher, ApplicationListener;

@safe:

@("getStateReturnsState") unittest
{
    auto source = new Object;
    const state = LivenessState.CORRECT;
    auto event = new AvailabilityChangeEvent!LivenessState(source, state);
    assert(event.getState() == state);
}

/// The mocked context: records the events published through it.
private final class RecordingPublisher : ApplicationEventPublisher
{
    ApplicationEvent[] events;

    void publishEventErased(ApplicationEvent event)
    {
        events ~= event;
    }
}

@("publishPublishesEvent") unittest
{
    auto context = new RecordingPublisher;
    const state = LivenessState.CORRECT;
    AvailabilityChangeEvent!LivenessState.publish(context, state);
    assert(context.events.length == 1);
    auto event = cast(AvailabilityChangeEvent!LivenessState) context.events[0];
    assert(event !is null);
    assert(event.getSource() is cast(Object) context);
    assert(event.getState() == state);
}

/// `Config.onLivenessAvailabilityChange`.
private final class LivenessListener : ApplicationListener!(AvailabilityChangeEvent!LivenessState)
{
    int calls;

    override void onApplicationEvent(AvailabilityChangeEvent!LivenessState event)
    {
        calls++;
        assert(event.getState() == LivenessState.CORRECT);
    }
}

@("publishEvenToContextConsidersGenericType") unittest
{
    import flint.context.support : GenericApplicationContext;

    auto context = new GenericApplicationContext;
    auto listener = new LivenessListener;
    context.addApplicationListener(listener);
    context.refresh();
    scope (exit)
        context.close();
    AvailabilityChangeEvent!LivenessState.publish(context, LivenessState.CORRECT);
    AvailabilityChangeEvent!ReadinessState.publish(context, ReadinessState.ACCEPTING_TRAFFIC);
    assert(listener.calls == 1);
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
