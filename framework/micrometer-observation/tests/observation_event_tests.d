/*
 * Copyright 2026 VMware, Inc.
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
// Ported from micrometer-observation 1.18.0: micrometer-observation/src/test/java/io/micrometer/observation/ObservationEventTests.java
// Modified by the Flint authors.
module micrometer_observation_event_tests;

import flint.engine.aot.any : Any;
import flint.engine.aot.clock : currentTimeMillis;
import flint.engine.aot.objects : objectToString;
import flint.java.lang : Iterable;
import flint.java.util : Collections;
import flint.micrometer.common : KeyValue, KeyValues;
import flint.micrometer.observation : Observation;

@safe:

private alias Event = Observation.Event;

private final class CustomEvent : Event
{
    override string getName()
    {
        return "test";
    }

    mixin Event.Defaults;
}

@("defaultGetKeyValuesReturnsEmptyKeyValues")
unittest
{
    Event event = new CustomEvent;
    assert(event.getContextualName() == "test" && event.getWallTime() == 0);
    assert(event.getLowCardinalityKeyValues() is KeyValues.empty());
    assert(event.getHighCardinalityKeyValues() is KeyValues.empty());
    assert(event.getKeyValues() is KeyValues.empty());
}

@("eventOfNameHasDefaultKeyValuesAndWallTime")
unittest
{
    const before = currentTimeMillis();
    Event event = Event.of("myEvent");
    const after = currentTimeMillis();

    assert(event.getName() == "myEvent" && event.getContextualName() == "myEvent");
    assert(before <= event.getWallTime() && event.getWallTime() <= after);
    assertEmptyKeyValues(event);
}

@("eventOfNameAndContextualNameHasDefaultKeyValues")
unittest
{
    const before = currentTimeMillis();
    Event event = Event.of("myEvent", "contextual %s");
    const after = currentTimeMillis();

    assert(event.getName() == "myEvent" && event.getContextualName() == "contextual %s");
    assert(before <= event.getWallTime() && event.getWallTime() <= after);
    assertEmptyKeyValues(event);
}

@("eventOfNameContextualNameAndWallTimeHasDefaultKeyValues")
unittest
{
    Event event = Event.of("myEvent", "contextual", 123_456);
    assertMetadata(event);
    assertEmptyKeyValues(event);
}

@("eventWithHighCardinalityKeyValues")
unittest
{
    auto high = KeyValues.of("hk1", "hv1", "hk2", "hv2");
    auto event = Event.of("myEvent", "contextual", 123_456, high);

    assertMetadata(event);
    assert(event.getLowCardinalityKeyValues() is KeyValues.empty());
    assert(event.getHighCardinalityKeyValues() is high && event.getKeyValues() is high);
}

@("eventWithHighAndLowCardinalityKeyValues")
unittest
{
    auto high = KeyValues.of("hk1", "hv1");
    auto low = KeyValues.of("lk1", "lv1");
    auto event = Event.of("myEvent", "contextual", 123_456, high, low);

    assertMetadata(event);
    assert(event.getHighCardinalityKeyValues() is high && event.getLowCardinalityKeyValues() is low);
    assert(event.getKeyValues().equals(KeyValues.of("hk1", "hv1", "lk1", "lv1")));
}

@("eventWithIterableKeyValues")
unittest
{
    Iterable!KeyValue values = Collections.singletonList!KeyValue(KeyValue.of("k1", "v1"));
    auto event = Event.of("myEvent", "contextual", 123_456, values);
    auto expected = KeyValues.of("k1", "v1");

    assert(event.getHighCardinalityKeyValues().equals(expected));
    assert(event.getKeyValues().equals(expected));
}

@("formatPreservesWallTimeAndKeyValues")
unittest
{
    auto high = KeyValues.of("detail", "timeout");
    auto low = KeyValues.of("attempt", "2");
    auto event = Event.of("retry", "attempt %s failed", 9999, high, low);

    auto formatted = event.format(2);
    assert(formatted.getName() == "retry" && formatted.getContextualName() == "attempt 2 failed");
    assert(formatted.getWallTime() == 9999);
    assert(formatted.getHighCardinalityKeyValues() is high && formatted.getLowCardinalityKeyValues() is low);
    assert(formatted.getKeyValues().equals(low.and(high)));
    assert(event.getContextualName() == "attempt %s failed");
}

@("toStringExcludesKeyValues")
unittest
{
    auto event = Event.of("myEvent", "contextual", 123_456, KeyValues.of("k1", "v1"));
    assert(objectToString(cast(
            Object) event) == "event.name='myEvent', event.contextualName='contextual', event.wallTime=123456");
}

@("boxed format arguments and signed explicit timestamps")
unittest
{
    auto event = Event.of("phase", "%2$s:%1$04d", long.min, KeyValues.of("id", "high"), KeyValues.of("id", "low"));
    Any[2] args = [Any.of(7), Any.of("warm")];
    assert(event.format(args[]).getContextualName() == "warm:0007");
    assert(event.getKeyValues().equals(KeyValues.of("id", "high")));
    enum expected = "event.name='phase', event.contextualName='%2$s:%1$04d', event.wallTime=-9223372036854775808";
    assert(objectToString(cast(Object) event) == expected);
}

private final class TaggedEvent : Event
{
    override string getName()
    {
        return "tagged";
    }

    override string getContextualName()
    {
        return "tagged %s";
    }

    override KeyValues getLowCardinalityKeyValues()
    {
        return KeyValues.of("category", "test");
    }

    mixin Event.Defaults;
}

@("a concrete Event can use the variadic default formatter")
unittest
{
    auto event = new TaggedEvent;
    Event view = event;
    assert(view.getKeyValues().equals(KeyValues.of("category", "test")));
    auto formatted = event.format("value");
    assert(formatted.getContextualName() == "tagged value");
    assert(formatted.getKeyValues().equals(view.getKeyValues()));
}

@("format preserves an empty contextual name")
unittest
{
    auto formatted = Event.of("phase", "%.0s", 0).format("warm");
    assert(formatted.getContextualName() !is null && formatted.getContextualName().length == 0);
    assert(formatted.format().getContextualName() !is null);
}

private void assertEmptyKeyValues(Event event)
{
    assert(event.getLowCardinalityKeyValues() is KeyValues.empty());
    assert(event.getHighCardinalityKeyValues() is KeyValues.empty());
    assert(event.getKeyValues() is KeyValues.empty());
}

private void assertMetadata(Event event)
{
    assert(event.getName() == "myEvent" && event.getContextualName() == "contextual");
    assert(event.getWallTime() == 123_456);
}
