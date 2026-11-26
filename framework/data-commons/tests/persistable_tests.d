// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/support/PersistableIsNewStrategyUnitTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module persistable_tests;

import flint.data.domain : Persistable;
import flint.data.support : IsNewStrategy, PersistableIsNewStrategy;
import flint.java.lang : IllegalArgumentException;
import std.exception : assertThrown;
import std.typecons : Nullable;

@safe:

private final class PersistableEntity : Persistable!long
{
    bool newEntity = true;
    Nullable!long id;

    override Nullable!long getId()
    {
        return id;
    }

    override bool isNew()
    {
        return newEntity;
    }
}

@("invokesPersistableIsNewForTest")
unittest
{
    IsNewStrategy strategy = PersistableIsNewStrategy.INSTANCE;
    auto entity = new PersistableEntity();
    assert(entity.getId().isNull);
    assert(strategy.isNew(entity));

    entity.id = Nullable!long(0);
    assert(!entity.getId().isNull && entity.getId().get() == 0);
    assert(strategy.isNew(entity));

    entity.newEntity = false;
    assert(!strategy.isNew(entity));
}

@("rejectsNonPersistableEntity")
unittest
{
    IsNewStrategy strategy = PersistableIsNewStrategy.INSTANCE;
    assertThrown!IllegalArgumentException(strategy.isNew(new Object()));
    assertThrown!IllegalArgumentException(strategy.isNew(null));
}

@("Reference identifiers use plain null")
unittest
{
    static final class Entity : Persistable!Object
    {
        override Object getId()
        {
            return null;
        }

        override bool isNew()
        {
            return false;
        }
    }

    auto entity = new Entity();
    assert(entity.getId() is null);
    assert(!PersistableIsNewStrategy.INSTANCE.isNew(entity));
}

@("The fieldless strategy is shared without allocation")
unittest
{
    static PersistableIsNewStrategy instance() @nogc nothrow
    {
        return PersistableIsNewStrategy.INSTANCE;
    }

    assert(instance() is instance());
}

@("The strategy exposes the Java enum constant")
unittest
{
    auto strategy = PersistableIsNewStrategy.INSTANCE;
    assert(strategy.name() == "INSTANCE");
    assert(strategy.ordinal() == 0);
    assert(strategy.toString() == "INSTANCE");
    assert(PersistableIsNewStrategy.values() == [strategy]);
    assert(PersistableIsNewStrategy.valueOf("INSTANCE") is strategy);
    assertThrown!IllegalArgumentException(PersistableIsNewStrategy.valueOf("Different"));
    static assert(!__traits(compiles, new PersistableIsNewStrategy()));
}
