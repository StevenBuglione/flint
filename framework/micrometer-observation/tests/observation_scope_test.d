module micrometer_observation_scope_test;

import flint.java.lang : AutoCloseable;
import flint.micrometer.observation : Observation;

@safe:

private final class TestObservation : Observation
{
    private Observation.Context context;

    this()
    {
        context = new Observation.Context;
    }

    override Observation.ContextView getContextView()
    {
        return context;
    }
}

private alias Scope = Observation.Scope;

private final class TestScope : Scope
{
    private Observation observation;
    bool closed;

    this(Observation observation)
    {
        this.observation = observation;
    }

    override Observation getCurrentObservation()
    {
        return observation;
    }

    override void close()
    {
        closed = true;
    }

    deprecated override void reset()
    {
        observation = null;
    }

    deprecated override void makeCurrent()
    {
        closed = false;
    }

    mixin Scope.Defaults;
}

@("a custom observation scope is closeable and has no preceding scope by default")
unittest
{
    auto observation = new TestObservation;
    auto custom = new TestScope(observation);
    Scope view = custom;
    assert(view.getCurrentObservation() is observation);
    assert(view.getPreviousObservationScope() is null && !view.isNoop());

    AutoCloseable resource = view;
    resource.close();
    assert(custom.closed);
}
