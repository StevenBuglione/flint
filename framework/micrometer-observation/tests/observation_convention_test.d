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
// Ported from micrometer-observation 1.18.0: micrometer-observation/src/test/java/io/micrometer/observation/ObservationConventionTest.java
// Modified by the Flint authors.
module micrometer_observation_convention_test;

import core.memory : GC;
import flint.micrometer.common : KeyValues;
import flint.micrometer.observation : GlobalObservationConvention, KeyValuesConvention, Observation,
    ObservationConvention;
import std.typecons : Nullable;

@safe:

private alias ContextConvention = ObservationConvention!(Observation.Context);

private final class TestObservationConvention : ContextConvention
{
    override bool supportsContext(Observation.Context context)
    {
        return true;
    }

    mixin ContextConvention.Defaults;
}

@("keyValuesShouldBeEmptyByDefault")
unittest
{
    ContextConvention convention = new TestObservationConvention;
    auto context = new Observation.Context;
    assert(convention.getLowCardinalityKeyValues(context) is KeyValues.empty());
    assert(convention.getHighCardinalityKeyValues(context) is KeyValues.empty());
    assert(convention.getName().isNull);
    assert(convention.getContextualName(context).isNull);
}

@("EMPTY is a shared convention that declines every context")
@system unittest
{
    auto context = new Observation.Context;
    auto convention = ContextConvention.EMPTY;
    const before = GC.allocatedInCurrentThread();
    assert(ContextConvention.EMPTY is convention);
    assert(!convention.supportsContext(context));
    assert(!convention.supportsContext(null));
    assert(convention.getLowCardinalityKeyValues(context) is KeyValues.empty());
    assert(convention.getHighCardinalityKeyValues(context) is KeyValues.empty());
    assert(convention.getName().isNull && convention.getContextualName(context).isNull);
    assert(GC.allocatedInCurrentThread() == before);
}

private final class HttpContext : Observation.Context
{
    string method = "GET";
}

private alias HttpConventionContract = ObservationConvention!HttpContext;

private struct WrappedContext
{
    Observation.Context context;
    alias context this;
}

private final class ContextAlias
{
    Observation.Context context;
    alias context this;
}

static assert(!is(ObservationConvention!WrappedContext));
static assert(!is(GlobalObservationConvention!ContextAlias));

private final class HttpConvention : GlobalObservationConvention!HttpContext
{
    override bool supportsContext(Observation.Context context)
    {
        return cast(HttpContext) context !is null;
    }

    override KeyValues getLowCardinalityKeyValues(HttpContext context)
    {
        return KeyValues.of("method", context.method);
    }

    override Nullable!string getName()
    {
        return Nullable!string("http.request");
    }

    mixin HttpConventionContract.Defaults;
}

@("a global convention uses the declared context subtype")
unittest
{
    HttpConventionContract convention = new HttpConvention;
    const KeyValuesConvention marker = convention;
    auto context = new HttpContext;
    assert(marker !is null && convention.supportsContext(context));
    assert(HttpConventionContract.EMPTY is ContextConvention.EMPTY);
    assert(!convention.supportsContext(new Observation.Context));
    assert(convention.getName().get() == "http.request");
    assert(convention.getContextualName(context).isNull);
    assert(convention.getLowCardinalityKeyValues(context).equals(KeyValues.of("method", "GET")));
    assert(convention.getHighCardinalityKeyValues(context) is KeyValues.empty());
    static assert(!__traits(compiles, convention.getLowCardinalityKeyValues(new Observation.Context)));
}
