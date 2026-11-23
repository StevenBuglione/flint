// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/availability/
// ApplicationAvailabilityBeanTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the context registers the bean as Flint AOT's generated definition would;
// Mockito's Log is a recording one; `getState(Class)` is `getState!S`.
module boot_tests.application_availability_bean_test;

import flint.boot.availability : ApplicationAvailabilityBean, AvailabilityChangeEvent, LivenessState, ReadinessState;
import flint.context.support : GenericApplicationContext;

@safe:

private struct Setup
{
    GenericApplicationContext context;
    ApplicationAvailabilityBean availability;
}

private Setup setup()
{
    Setup result;
    result.context = new GenericApplicationContext;
    result.context.registerBean!ApplicationAvailabilityBean("applicationAvailabilityBean",
            () => new ApplicationAvailabilityBean);
    result.context.refresh();
    result.availability = result.context.getBean!ApplicationAvailabilityBean();
    return result;
}

@("getLivenessStateWhenNoEventHasBeenPublishedReturnsDefaultState") unittest
{
    auto s = setup();
    assert(s.availability.getLivenessState() == LivenessState.BROKEN);
}

@("getLivenessStateWhenEventHasBeenPublishedReturnsPublishedState") unittest
{
    auto s = setup();
    AvailabilityChangeEvent!LivenessState.publish(s.context, LivenessState.CORRECT);
    assert(s.availability.getLivenessState() == LivenessState.CORRECT);
}

@("getReadinessStateWhenNoEventHasBeenPublishedReturnsDefaultState") unittest
{
    auto s = setup();
    assert(s.availability.getReadinessState() == ReadinessState.REFUSING_TRAFFIC);
}

@("getReadinessStateWhenEventHasBeenPublishedReturnsPublishedState") unittest
{
    auto s = setup();
    AvailabilityChangeEvent!ReadinessState.publish(s.context, ReadinessState.ACCEPTING_TRAFFIC);
    assert(s.availability.getReadinessState() == ReadinessState.ACCEPTING_TRAFFIC);
}

version (FlintAvailabilityCustomStates)
{
    // Gap: only LivenessState and ReadinessState are availability states (D enums cannot implement Boot's
    // AvailabilityState), and there is no getLastChangeEvent.
    import flint.boot.availability : AvailabilityState;

    /// `TestState`.
    enum TestState : AvailabilityState
    {
        ONE,
        TWO
    }

    @("getStateWhenNoEventHasBeenPublishedReturnsDefaultState") unittest
    {
        auto s = setup();
        assert(s.availability.getState!TestState() is null);
        assert(s.availability.getState!TestState(TestState.ONE) == TestState.ONE);
    }

    @("getStateWhenEventHasBeenPublishedReturnsPublishedState") unittest
    {
        auto s = setup();
        AvailabilityChangeEvent!TestState.publish(s.context, TestState.TWO);
        assert(s.availability.getState!TestState() == TestState.TWO);
        assert(s.availability.getState!TestState(TestState.ONE) == TestState.TWO);
    }

    @("getLastChangeEventWhenNoEventHasBeenPublishedReturnsDefaultState") unittest
    {
        auto s = setup();
        assert(s.availability.getLastChangeEvent!TestState() is null);
    }

    @("getLastChangeEventWhenEventHasBeenPublishedReturnsPublishedState") unittest
    {
        auto s = setup();
        AvailabilityChangeEvent!TestState.publish(s.context, TestState.TWO);
        assert(s.availability.getLastChangeEvent!TestState() !is null);
    }
}

version (FlintAvailabilityLogging)
{
    // Gap: availability changes are not logged ("Application availability state ... changed to ...").
    import flint.boot.internal.log : Log, LogSettings;
    import std.algorithm.searching : canFind;

    private string[] logged;

    private Setup setupWithLog()
    {
        logged = null;
        auto settings = new LogSettings;
        settings.sink = (string line) { logged ~= line; };
        Setup result;
        result.context = new GenericApplicationContext;
        auto log = new Log("flint.boot.availability.ApplicationAvailabilityBean", settings);
        result.context.registerBean!ApplicationAvailabilityBean("applicationAvailabilityBean",
                () => new ApplicationAvailabilityBean(log));
        result.context.refresh();
        result.availability = result.context.getBean!ApplicationAvailabilityBean();
        return result;
    }

    private bool loggedLine(string text)
    {
        foreach (line; logged)
        {
            if (line.canFind(text))
                return true;
        }
        return false;
    }

    @("stateChangesAreLogged") unittest
    {
        auto s = setupWithLog();
        AvailabilityChangeEvent!LivenessState.publish(s.context, LivenessState.CORRECT);
        assert(loggedLine("Application availability state LivenessState changed to CORRECT"));
        AvailabilityChangeEvent!LivenessState.publish(s.context, LivenessState.BROKEN);
        assert(loggedLine("Application availability state LivenessState changed from CORRECT to BROKEN"));
    }

    @("stateChangesAreLoggedWithExceptionSource") unittest
    {
        import flint.java.io : IOException;

        auto s = setupWithLog();
        AvailabilityChangeEvent!LivenessState.publish(s.context,
                new IOException("connection error"), LivenessState.BROKEN);
        assert(loggedLine("Application availability state LivenessState changed to BROKEN: "
                ~ "flint.java.io.IOException: connection error"));
    }

    /// `CustomEventSource`.
    final class CustomEventSource
    {
    }

    @("stateChangesAreLoggedWithOtherSource") unittest
    {
        auto s = setupWithLog();
        AvailabilityChangeEvent!LivenessState.publish(s.context, new CustomEventSource, LivenessState.BROKEN);
        assert(loggedLine("Application availability state LivenessState changed to BROKEN: "
                ~ "boot_tests.application_availability_bean_test.CustomEventSource"));
    }
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
