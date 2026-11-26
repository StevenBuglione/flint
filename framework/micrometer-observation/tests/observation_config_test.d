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
import flint.micrometer.observation : GlobalObservationConvention, Observation, ObservationConvention,
    ObservationFilter, ObservationHandler, ObservationPredicate, ObservationRegistry;
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
    static assert(!__traits(compiles, config.getObservationFilters().front = filter));
    auto first = config.getObservationFilters();
    assert(config.observationFilter(context => context.addHighCardinalityKeyValue(KeyValue.of("source",
            "replacement"))) is config);

    auto filters = config.getObservationFilters();
    assert(first.front is filter && filters.front is filter);
    first.popFront();
    assert(first.empty);
    auto context = new Observation.Context;
    size_t count;
    foreach (registered; filters)
    {
        count++;
        context = registered.map(context);
    }
    assert(count == 2);
    assert(context.getHighCardinalityKeyValue("source").getValue() == "replacement");
}

@("both filter overloads preserve explicitly null registration")
unittest
{
    auto config = new Config;
    alias Map = Observation.Context delegate(Observation.Context) @safe;
    assert(config.observationFilter(cast(ObservationFilter) null).observationFilter(cast(Map) null)
            .observationFilter(null) is config);
    size_t count;
    foreach (filter; config.getObservationFilters())
    {
        count++;
        assert(filter is null);
    }
    assert(count == 3);
}

private final class TimedContext : Observation.Context
{
}

private alias TimedHandlerContract = ObservationHandler!TimedContext;
private alias BaseHandlerContract = ObservationHandler!(Observation.Context);

private final class TimedHandler : TimedHandlerContract
{
    override bool supportsContext(Observation.Context context)
    {
        return cast(TimedContext) context !is null;
    }

    mixin TimedHandlerContract.Defaults;
}

private final class UniversalHandler : BaseHandlerContract
{
    override bool supportsContext(Observation.Context context)
    {
        return true;
    }

    mixin BaseHandlerContract.Defaults;
}

@("registration retains original handler identity and subtype selection")
unittest
{
    auto config = new Config;
    auto timed = new TimedHandler;
    auto general = new UniversalHandler;
    assert(config.observationHandler(timed).observationHandler(general) is config);

    auto handlers = config.getObservationHandlers();
    assert(!handlers.empty && handlers.front.source() is timed);
    auto context = new TimedContext;
    assert(handlers.front.supportsContext(context));
    assert(!handlers.front.supportsContext(new Observation.Context));
    handlers.popFront();
    assert(!handlers.empty && handlers.front.source() is general);
    handlers.popFront();
    assert(handlers.empty);
}

@("handler registrations during callbacks do not alter a reader's snapshot")
unittest
{
    auto config = new Config;
    auto later = new UniversalHandler;
    config.observationHandler((context) { config.observationHandler(later); return true; });

    auto before = config.getObservationHandlers();
    assert(before.front.supportsContext(null));
    before.popFront();
    assert(before.empty);
    auto after = config.getObservationHandlers();
    after.popFront();
    assert(!after.empty && after.front.source() is later);
}

@("handler null registration keeps Java's ordering and fails when invoked")
unittest
{
    auto config = new Config;
    alias Support = bool delegate(Observation.Context) @safe;
    assert(config.observationHandler(null).observationHandler(cast(BaseHandlerContract) null)
            .observationHandler(cast(Support) null) is config);
    size_t count;
    foreach (handler; config.getObservationHandlers())
    {
        count++;
        assert(handler.source() is null);
        assertThrown!NullPointerException(handler.supportsContext(null));
    }
    assert(count == 3);
}

private alias TimedConventionContract = ObservationConvention!TimedContext;
private alias DefaultConventionContract = ObservationConvention!(Observation.Context);

private final class TimedGlobalConvention : GlobalObservationConvention!TimedContext
{
    override bool supportsContext(Observation.Context context)
    {
        return cast(TimedContext) context !is null;
    }

    mixin TimedConventionContract.Defaults;
}

private final class GeneralGlobalConvention : GlobalObservationConvention!(Observation.Context)
{
    override bool supportsContext(Observation.Context context)
    {
        return true;
    }

    mixin DefaultConventionContract.Defaults;
}

@("the first matching global convention wins across context specializations")
unittest
{
    auto config = new Config;
    auto timed = new TimedGlobalConvention;
    auto nextTimed = new TimedGlobalConvention;
    auto general = new GeneralGlobalConvention;
    config.observationConvention(timed).observationConvention(nextTimed);
    assert(config.observationConvention(general) is config);
    DefaultConventionContract fallback = DefaultConventionContract.EMPTY;

    assert(config.getObservationConvention(new TimedContext, fallback) is timed);
    assert(config.getObservationConvention(new Observation.Context, fallback) is general);
    assert(config.getObservationConvention(new TimedContext, cast(DefaultConventionContract) null) is timed);
    assert(config.getObservationHandlers().empty);
}

@("a nonmatching registration uses the exact default convention or rejects a missing default")
unittest
{
    auto config = new Config;
    config.observationConvention(new TimedGlobalConvention);
    auto context = new Observation.Context;
    DefaultConventionContract fallback = DefaultConventionContract.EMPTY;
    assert(config.getObservationConvention(context, fallback) is cast(Object) fallback);
    assertThrown!NullPointerException(config.getObservationConvention(context, cast(DefaultConventionContract) null));
}

@("conventions registered during selection appear on the next lookup")
unittest
{
    auto config = new Config;
    auto later = new TimedGlobalConvention;
    config.observationConvention((context) { config.observationConvention(later); return false; });
    auto context = new TimedContext;
    DefaultConventionContract fallback = DefaultConventionContract.EMPTY;
    assert(config.getObservationConvention(context, fallback) is cast(Object) fallback);
    assert(config.getObservationConvention(context, fallback) is later);
}

@("delegate conventions can win and null conventions fail only when reached")
unittest
{
    auto config = new Config;
    config.observationConvention((context) => context is null);
    config.observationConvention(null);
    auto selected = config.getObservationConvention(null, cast(DefaultConventionContract) null);
    assert(selected !is null);
    assert(config.getObservationConvention(null, cast(DefaultConventionContract) null) is selected);
    assertThrown!NullPointerException(config.getObservationConvention(new Observation.Context,
            DefaultConventionContract.EMPTY));

    alias Supports = bool delegate(Observation.Context) @safe;
    foreach (registered; [
        new Config().observationConvention(cast(GlobalObservationConvention!TimedContext) null),
        new Config().observationConvention(cast(Supports) null)
    ])
        assertThrown!NullPointerException(registered.getObservationConvention(null, DefaultConventionContract.EMPTY));
}

private interface LeftFilter : ObservationFilter
{
}

private interface RightFilter : ObservationFilter
{
}

private interface CombinedFilter : LeftFilter, RightFilter
{
}

private final class IdentityFilter : CombinedFilter
{
    override Observation.Context map(Observation.Context context)
    {
        return context;
    }
}

@("a snapshot retains the exact registered interface reference")
unittest
{
    auto config = new Config;
    ObservationFilter filter = cast(RightFilter) new IdentityFilter;
    config.observationFilter(filter);
    assert(config.getObservationFilters().front is filter);
}
