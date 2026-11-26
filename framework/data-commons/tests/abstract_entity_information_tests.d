// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/repository/core/support/AbstractEntityInformationUnitTests.java
// Copyright 2011-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module abstract_entity_information_tests;

import flint.data.repository.core.support : AbstractEntityInformation;
import flint.java.classref : ClassRef, classOf;
import flint.java.lang : IllegalArgumentException, Long;
import std.typecons : Nullable;

@safe:

private final class ObjectInformation : AbstractEntityInformation!(Object, Object)
{
    override Object getId(Object entity)
    {
        return entity;
    }

    override ClassRef getIdType()
    {
        return classOf!Object;
    }
}

private final class Entity(ID)
{
    Nullable!ID id;
}

private final class FieldInformation(ID, Token = ID) : AbstractEntityInformation!(Entity!ID, ID)
{
    override Nullable!ID getId(Entity!ID entity)
    {
        return entity.id;
    }

    override ClassRef getIdType()
    {
        return classOf!Token;
    }
}

@("considersEntityNewIfGetIdReturnsNull")
unittest
{
    auto information = new ObjectInformation;
    assert(information.getJavaType() == classOf!Object);
    assert(information.isNew(null));
    assert(!information.isNew(new Object));
}

@("detectsNewStateForPrimitiveIds")
unittest
{
    auto information = new FieldInformation!long;
    auto entity = new Entity!long;
    entity.id = 0L;
    assert(information.isNew(entity));
    entity.id = 5L;
    assert(!information.isNew(entity));
}

@("detectsNewStateForPrimitiveWrapperIds")
unittest
{
    auto information = new FieldInformation!(long, Long);
    auto entity = new Entity!long;
    assert(information.isNew(entity));
    entity.id = 0L;
    assert(!information.isNew(entity));
    entity.id = 5L;
    assert(!information.isNew(entity));
}

@("rejectsUnsupportedPrimitiveIdType")
unittest
{
    auto information = new FieldInformation!bool;
    auto entity = new Entity!bool;
    entity.id = false;
    try
    {
        information.isNew(entity);
        assert(0, "The boolean identifier should be rejected");
    }
    catch (IllegalArgumentException error)
    {
        assert(error.msg == "Unsupported primitive id type boolean");
    }
}

@("Floating ID newness uses Java Number.longValue zero semantics")
unittest
{
    auto information = new FieldInformation!double;
    auto entity = new Entity!double;
    foreach (numericZero; [-0.75, 0.0, 0.75, double.nan])
    {
        entity.id = numericZero;
        assert(information.isNew(entity));
    }
    foreach (nonZero; [-double.infinity, -1.0, 1.0, double.infinity])
    {
        entity.id = nonZero;
        assert(!information.isNew(entity));
    }
}
