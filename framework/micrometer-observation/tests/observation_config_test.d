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
// Local configuration tests based on micrometer-observation 1.18.0 ObservationTests.java.
// Modified by the Flint authors.
module flint.micrometer.observation_config_test;

import flint.java.lang : NullPointerException;
import flint.micrometer.common : KeyValue;
import flint.micrometer.observation : Observation, ObservationFilter, ObservationPredicate, ObservationRegistry;
import std.exception : assertThrown;
import std.typecons : Nullable;

@safe:

private alias Config = ObservationRegistry.ObservationConfig;

private final class ChildPredicate : ObservationPredicate
{
    override bool test(string name, Observation.Context context)
    {
        return name != "child" || context.getParentObservation() !is null;
    }
}

private final class AddTag : ObservationFilter
{
    override Observation.Context map(Observation.Context context)
    {
        return context.addHighCardinalityKeyValue(KeyValue.of("source", "filter"));
    }
}

@("predicate registration preserves order and stops on the first rejection")
unittest
{
    auto config = new Config;
    auto context = new Observation.Context;
    assert(config.isObservationEnabled(Nullable!string("child"), context));
    uint calls;
    assert(config.observationPredicate((name, supplied) {
            assert(name == "child" && supplied is context);
            calls++;
            return true;
        }).observationPredicate(new ChildPredicate).observationPredicate((name, supplied) {
            assert(false, "a later predicate ran after a rejection");
            return true;
        }) is config);

    assert(!config.isObservationEnabled(Nullable!string("child"), context));
    assert(calls == 1);
}

@("predicate registration during evaluation affects only the next snapshot")
unittest
{
    auto config = new Config;
    uint appendedCalls;
    config.observationPredicate((name, context) {
        config.observationPredicate((laterName, laterContext) { appendedCalls++; return false; });
        return true;
    });

    assert(config.isObservationEnabled(Nullable!string.init, null));
    assert(appendedCalls == 0);
    assert(!config.isObservationEnabled(Nullable!string.init, null));
    assert(appendedCalls == 1);
}

@("predicate callbacks distinguish a missing name from an empty name")
unittest
{
    auto config = new Config;
    config.observationPredicate((name, context) => name is null && context is null);
    assert(config.isObservationEnabled(Nullable!string.init, null));
    assert(!config.isObservationEnabled(Nullable!string(""), null));
    const string emptySlice = null;
    const presentName = Nullable!string(emptySlice);
    assert(!presentName.isNull && !config.isObservationEnabled(presentName, null));

    alias Test = bool delegate(string, Observation.Context) @safe;
    foreach (registered; [
        new Config().observationPredicate(cast(ObservationPredicate) null),
        new Config().observationPredicate(cast(Test) null)
    ])
        assertThrown!NullPointerException(registered.isObservationEnabled(Nullable!string.init, null));
}

@("filter registration retains ordered snapshots and supports both callback forms")
unittest
{
    auto config = new Config;
    auto filter = new AddTag;
    assert(config.observationFilter(filter) is config);
    static assert(!__traits(compiles, config.getObservationFilters()[0] = filter));
    const first = config.getObservationFilters();
    assert(config.observationFilter(context => context.addHighCardinalityKeyValue(KeyValue.of("source",
            "replacement"))) is config);

    auto filters = config.getObservationFilters();
    assert(first.length == 1 && filters.length == 2);
    assert(first[0] is filter && filters[0] is filter);
    auto context = new Observation.Context;
    for (size_t index; index < filters.length; index++)
        context = filters[index].map(context);
    assert(context.getHighCardinalityKeyValue("source").getValue() == "replacement");
}

@("both filter overloads preserve explicitly null registration")
unittest
{
    auto config = new Config;
    alias Map = Observation.Context delegate(Observation.Context) @safe;
    assert(config.observationFilter(cast(ObservationFilter) null).observationFilter(cast(Map) null)
            .observationFilter(null) is config);
    const filters = config.getObservationFilters();
    assert(filters.length == 3 && filters[0] is null && filters[1] is null && filters[2] is null);
}
