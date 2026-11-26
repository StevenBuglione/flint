/*
 * Copyright 2022 VMware, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
// Local callback tests based on micrometer-observation 1.18.0 ObservationTests.java.
// Modified by the Flint authors.
module micrometer_observation_callbacks_test;

import flint.java.util.function_ : BiPredicate;
import flint.micrometer.common : KeyValue;
import flint.micrometer.observation : Observation, ObservationFilter, ObservationHandler, ObservationPredicate;

@safe:

private final class ChildPredicate : ObservationPredicate
{
    override bool test(string name, Observation.Context context)
    {
        return name != "child" || context.getParentObservation() !is null;
    }
}

private final class ParentObservation : Observation
{
    private Observation.Context context;

    this(Observation.Context context)
    {
        this.context = context;
    }

    override Observation.ContextView getContextView()
    {
        return context;
    }
}

@("an observation predicate receives the name and context as a Java BiPredicate")
unittest
{
    ObservationPredicate predicate = new ChildPredicate;
    BiPredicate!(string, Observation.Context) test = predicate;
    auto child = new Observation.Context;

    assert(test.test("parent", child));
    assert(!test.test("child", child));
    child.setParentObservation(new ParentObservation(new Observation.Context));
    assert(test.test("child", child));
}

private final class SuffixFilter : ObservationFilter
{
    override Observation.Context map(Observation.Context context)
    {
        auto value = context.getHighCardinalityKeyValue("foo");
        assert(value !is null);
        return context.addHighCardinalityKeyValue(KeyValue.of(value.getKey(), value.getValue() ~ "-modified"));
    }
}

@("an observation filter can replace a high-cardinality key on its input context")
unittest
{
    ObservationFilter filter = new SuffixFilter;
    auto context = new Observation.Context;
    context.addHighCardinalityKeyValue(KeyValue.of("foo", "FOO"));

    assert(filter.map(context) is context);
    assert(context.getHighCardinalityKeyValue("foo").getValue() == "FOO-modified");
}

private final class RecordingContext : Observation.Context
{
    Observation.Event event;
    bool stopped;
}

private alias RecordingHandlerContract = ObservationHandler!RecordingContext;

private final class RecordingHandler : RecordingHandlerContract
{
    override bool supportsContext(Observation.Context context)
    {
        return cast(RecordingContext) context !is null;
    }

    override void onEvent(Observation.Event event, RecordingContext context)
    {
        context.event = event;
    }

    override void onStop(RecordingContext context)
    {
        context.stopped = true;
    }

    mixin RecordingHandlerContract.Defaults;
}

@("typed event and stop callbacks dispatch alongside no-op defaults")
unittest
{
    RecordingHandlerContract handler = new RecordingHandler;
    auto context = new RecordingContext;
    assert(handler.supportsContext(context));
    assert(!handler.supportsContext(new Observation.Context));

    handler.onStart(context);
    handler.onError(context);
    handler.onScopeOpened(context);
    handler.onScopeClosed(context);
    assert(context.event is null && !context.stopped);
    auto event = Observation.Event.of("converted", "converted", 100);
    handler.onEvent(event, context);
    assert(context.event is event && !context.stopped);
    handler.onStop(context);
    assert(context.stopped);
}

private final class DefaultHandler : RecordingHandlerContract
{
    override bool supportsContext(Observation.Context context)
    {
        return cast(RecordingContext) context !is null;
    }

    mixin RecordingHandlerContract.Defaults;
}

@("all inherited lifecycle callbacks leave the context untouched")
deprecated unittest
{
    RecordingHandlerContract handler = new DefaultHandler;
    auto context = new RecordingContext;
    auto event = Observation.Event.of("converted", "converted", 100);

    handler.onStart(context);
    handler.onEvent(event, context);
    handler.onError(context);
    handler.onScopeOpened(context);
    handler.onScopeReset(context);
    handler.onScopeClosed(context);
    handler.onStop(context);
    assert(context.event is null && !context.stopped);
}
