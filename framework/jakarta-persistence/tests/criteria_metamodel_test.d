/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.jakarta.persistence.criteria_metamodel_test;

import flint.jakarta.persistence.criteria : JoinType, Nulls;
import flint.jakarta.persistence.metamodel : BasicType, Bindable, StaticMetamodel, Type;
import flint.java.classref : ClassRef, classOf;
import std.traits : EnumMembers, getUDAs;

@safe:

private final class Owner
{
}

@StaticMetamodel(classOf!Owner)
private final class OwnerMetamodel
{
}

@("metamodel contracts expose class tokens through typed provider interfaces")
unittest
{
    static final class BasicLong : BasicType!long, Bindable!long
    {
        override Type!long.PersistenceType getPersistenceType()
        {
            return Type!long.PersistenceType.BASIC;
        }

        override ClassRef getJavaType()
        {
            return classOf!long;
        }

        override Bindable!long.BindableType getBindableType()
        {
            return Bindable!long.BindableType.PLURAL_ATTRIBUTE;
        }

        override ClassRef getBindableJavaType()
        {
            return classOf!long;
        }
    }

    auto descriptor = new BasicLong;
    Type!long persistentType = descriptor;
    Bindable!long binding = descriptor;
    assert(persistentType.getPersistenceType() == Type!long.PersistenceType.BASIC);
    assert(persistentType.getJavaType() == classOf!long);
    assert(binding.getBindableType() == Bindable!long.BindableType.PLURAL_ATTRIBUTE);
    assert(binding.getBindableJavaType() == classOf!long);

    static assert(is(Type!long.PersistenceType == Type!Owner.PersistenceType));
    static assert(is(Bindable!long.BindableType == Bindable!Owner.BindableType));
    static assert(getUDAs!(OwnerMetamodel, StaticMetamodel)[0].value == classOf!Owner);
}

@("Criteria option enums preserve Jakarta declaration order")
unittest
{
    static assert([EnumMembers!JoinType] == [JoinType.INNER, JoinType.LEFT, JoinType.RIGHT]);
    static assert([EnumMembers!Nulls] == [Nulls.NONE, Nulls.FIRST, Nulls.LAST]);
}
