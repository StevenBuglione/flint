// Ported from spring-boot v4.2.0: module/spring-boot-health/src/main/java/org/springframework/boot/health/application/AvailabilityStateHealthIndicator.java
// with LivenessStateHealthIndicator.java and ReadinessStateHealthIndicator.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the state type is a template parameter (R4) and the status mappings a callback
// over `add`/`addDefaultStatus`, as Boot's `Consumer<StatusMappings<S>>`.

/// `org.springframework.boot.health.application`: health indicators for the application itself.
module flint.boot.health.application;

import flint.boot.availability : ApplicationAvailability, LivenessState, ReadinessState, isAvailabilityState;
import flint.boot.health.contributor : AbstractHealthIndicator, Health, Status;

@safe:

/// Reports the health of an availability state, through a mapping from states to statuses.
class AvailabilityStateHealthIndicator(S) : AbstractHealthIndicator if (isAvailabilityState!S)
{
    private ApplicationAvailability applicationAvailability;
    private Status[S] statusMappings;
    private Status defaultStatus;

    /// Over `applicationAvailability`, with the mappings `mappings` adds.
    this(ApplicationAvailability applicationAvailability, void delegate(StatusMappings) @safe mappings)
    {
        import flint.java.lang : IllegalArgumentException, IllegalStateException;
        import std.conv : to;
        import std.traits : EnumMembers;

        if (applicationAvailability is null)
            throw new IllegalArgumentException("'applicationAvailability' must not be null");
        this.applicationAvailability = applicationAvailability;
        mappings(new StatusMappings);
        if (defaultStatus is null)
        {
            foreach (state; EnumMembers!S)
            {
                if (state !in statusMappings)
                    throw new IllegalStateException("StatusMappings does not include " ~ state.to!string);
            }
        }
    }

    protected override void doHealthCheck(Health.Builder builder)
    {
        import flint.java.lang : IllegalStateException;
        import std.conv : to;

        const state = getState(applicationAvailability);
        auto status = state in statusMappings ? statusMappings[state] : defaultStatus;
        if (status is null)
            throw new IllegalStateException("No mapping provided for " ~ state.to!string);
        builder.status(status);
    }

    /// The current state.
    protected abstract S getState(ApplicationAvailability applicationAvailability);

    /// Adds mappings from states to statuses.
    final class StatusMappings
    {
        /// Map `state` to `status`.
        void add(S state, Status status)
        {
            statusMappings[state] = status;
        }

        /// The status of states without a mapping.
        void addDefaultStatus(Status status)
        {
            defaultStatus = status;
        }
    }
}

/// `CORRECT` is `UP`, `BROKEN` is `DOWN`.
class LivenessStateHealthIndicator : AvailabilityStateHealthIndicator!LivenessState
{
    /// Over `availability`.
    this(ApplicationAvailability availability)
    {
        super(availability, (mappings) {
            mappings.add(LivenessState.CORRECT, Status.UP);
            mappings.add(LivenessState.BROKEN, Status.DOWN);
        });
    }

    protected override LivenessState getState(ApplicationAvailability applicationAvailability)
    {
        return applicationAvailability.getLivenessState();
    }
}

/// `ACCEPTING_TRAFFIC` is `UP`, `REFUSING_TRAFFIC` is `OUT_OF_SERVICE`.
class ReadinessStateHealthIndicator : AvailabilityStateHealthIndicator!ReadinessState
{
    /// Over `availability`.
    this(ApplicationAvailability availability)
    {
        super(availability, (mappings) {
            mappings.add(ReadinessState.ACCEPTING_TRAFFIC, Status.UP);
            mappings.add(ReadinessState.REFUSING_TRAFFIC, Status.OUT_OF_SERVICE);
        });
    }

    protected override ReadinessState getState(ApplicationAvailability applicationAvailability)
    {
        return applicationAvailability.getReadinessState();
    }
}
