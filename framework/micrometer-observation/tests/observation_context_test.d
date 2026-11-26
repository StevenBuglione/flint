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
// Ported from micrometer-observation 1.18.0: micrometer-observation/src/test/java/io/micrometer/observation/ObservationContextTest.java
// Modified by the Flint authors.
module micrometer_observation_context_test;

import flint.java.lang : NullPointerException;
import flint.micrometer.common : KeyValue, KeyValues;
import flint.micrometer.observation : Observation, ObservationView;
import std.exception : assertThrown;
import std.typecons : Nullable;

@safe:

@("sameKeyShouldOverrideKeyValue")
unittest
{
    auto context = new Observation.Context;
    auto low = KeyValue.of("low", "LOW");
    auto high = KeyValue.of("high", "HIGH");
    context.addLowCardinalityKeyValue(low);
    context.addHighCardinalityKeyValue(high);
    assert(context.getLowCardinalityKeyValue("low") is low);
    assert(context.getHighCardinalityKeyValue("high") is high);

    auto oldLow = context.getLowCardinalityKeyValues();
    auto newLow = KeyValue.of("low", "LOW-NEW");
    auto newHigh = KeyValue.of("high", "HIGH-NEW");
    context.addLowCardinalityKeyValue(newLow);
    context.addHighCardinalityKeyValue(newHigh);
    assert(context.getLowCardinalityKeyValue("low") is newLow);
    assert(context.getHighCardinalityKeyValue("high") is newHigh);
    assert(context.getLowCardinalityKeyValues().toString() == "[keyValue(low=LOW-NEW)]");
    assert(context.getHighCardinalityKeyValues().toString() == "[keyValue(high=HIGH-NEW)]");
    assert(oldLow.toString() == "[keyValue(low=LOW)]");
}

@("removingLowCardinalityKeysShouldBePossible")
unittest
{
    auto context = new Observation.Context;
    context.addLowCardinalityKeyValues(KeyValues.of(KeyValue.of("key", "VALUE"),
            KeyValue.of("key2", "VALUE2"), KeyValue.of("key3", "VALUE3"), KeyValue.of("key4", "VALUE4")));
    context.removeLowCardinalityKeyValue("key");
    context.removeLowCardinalityKeyValues("key3", "key4");
    assert(context.getLowCardinalityKeyValues().toString() == "[keyValue(key2=VALUE2)]");
}

@("removingHighCardinalityKeysShouldBePossible")
unittest
{
    auto context = new Observation.Context;
    context.addHighCardinalityKeyValues(KeyValues.of(KeyValue.of("key", "VALUE"),
            KeyValue.of("key2", "VALUE2"), KeyValue.of("key3", "VALUE3"), KeyValue.of("key4", "VALUE4")));
    context.removeHighCardinalityKeyValue("key");
    context.removeHighCardinalityKeyValues("key3", "key4");
    assert(context.getHighCardinalityKeyValues().toString() == "[keyValue(key2=VALUE2)]");
}

private final class Parent : Observation
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

@("context metadata keeps null distinct from an empty name")
unittest
{
    auto context = new Observation.Context;
    Observation.ContextView view = context;
    assert(view.getName().isNull && view.getContextualName().isNull);
    assert(view.getParentObservation() is null && view.getError() is null);

    ObservationView parent = new Parent(new Observation.Context);
    auto error = new Exception("failed");
    context.setName("");
    context.setContextualName(Nullable!string(""));
    context.setParentObservation(parent);
    context.setError(error);
    assert(!view.getName().isNull && view.getName().get() == "");
    assert(!view.getContextualName().isNull && view.getContextualName().get() == "");
    assert(view.getParentObservation() is parent && view.getError() is error);
    assert(parent.getContextView().getName().isNull);

    context.setContextualName(Nullable!string.init);
    context.setParentObservation(null);
    context.setError(null);
    assert(view.getContextualName().isNull && view.getParentObservation() is null && view.getError() is null);
}

@("combined snapshot uses the high-cardinality value for a shared key")
unittest
{
    auto context = new Observation.Context;
    assert(context.getAllKeyValues() is KeyValues.empty());
    assert(context.getHighCardinalityKeyValue("missing") is null);
    auto low = KeyValue.of("", "EMPTY-KEY");
    auto high = KeyValue.of("", "HIGH");
    assert(context.addLowCardinalityKeyValue(low).addHighCardinalityKeyValue(high) is context);
    assert(context.getLowCardinalityKeyValue("") is low);
    assert(context.getAllKeyValues().iterator().next() is high);
    assert(context.removeLowCardinalityKeyValues().removeHighCardinalityKeyValues() is context);
    assert(context.getAllKeyValues().iterator().next() is high);
    assertThrown!NullPointerException(context.removeHighCardinalityKeyValues(cast(const(string)[]) null));
    assertThrown!NullPointerException(context.addLowCardinalityKeyValues(null));
    assertThrown!NullPointerException(context.getHighCardinalityKeyValue(null));
    assertThrown!NullPointerException(context.addHighCardinalityKeyValue(null));
}

private final class TrackingContext : Observation.Context
{
    private bool removed;

    override Observation.Context removeLowCardinalityKeyValues(scope const(string)[] keys...)
    {
        assert(keys !is null && keys.length == 0);
        removed = true;
        return super.removeLowCardinalityKeyValues(keys);
    }
}

@("variadic removal dispatches even with no supplied keys")
unittest
{
    auto tracked = new TrackingContext;
    Observation.Context context = tracked;
    assert(context.removeLowCardinalityKeyValues() is context);
    assert(tracked.removed);
}
