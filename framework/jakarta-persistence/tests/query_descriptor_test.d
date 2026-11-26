/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.jakarta.persistence.query_descriptor_test;

import flint.jakarta.persistence : Parameter, TupleElement;
import flint.java.classref : ClassRef, classOf;
import std.typecons : Nullable;

@safe:

private final class QueryParameter : Parameter!long
{
    Nullable!string name;
    Nullable!int position;

    override Nullable!string getName()
    {
        return name;
    }

    override Nullable!int getPosition()
    {
        return position;
    }

    override ClassRef getParameterType()
    {
        return classOf!long;
    }
}

private class Owner
{
}

private final class PreferredOwner : Owner
{
}

private final class OwnerSelection : TupleElement!Owner
{
    Nullable!string aliasName;

    override Nullable!string getAlias()
    {
        return aliasName;
    }

    override ClassRef getJavaType()
    {
        return classOf!PreferredOwner;
    }
}

@("query parameter metadata preserves named and positional forms")
unittest
{
    auto probe = new QueryParameter;
    Parameter!long parameter = probe;
    probe.position = Nullable!int(1);
    assert(parameter.getName().isNull);
    assert(parameter.getPosition().get() == 1);
    assert(parameter.getParameterType() == classOf!long);

    probe.position.nullify();
    probe.name = Nullable!string("ownerId");
    assert(parameter.getName().get() == "ownerId");
    assert(parameter.getPosition().isNull);
}

@("a tuple element can expose a subtype token and distinguish an empty alias from absence")
unittest
{
    auto probe = new OwnerSelection;
    TupleElement!Owner element = probe;
    assert(element.getAlias().isNull);
    assert(element.getJavaType() == classOf!PreferredOwner);

    probe.aliasName = Nullable!string("");
    assert(!element.getAlias().isNull);
    assert(element.getAlias().get() == "");
}
