// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/support/{IsNewStrategy,PersistableIsNewStrategy}.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.support.is_new_strategy;

import flint.data.domain.persistable : PersistableState;
import flint.engine.aot.objects : statelessInstance;
import flint.java.lang : IllegalArgumentException, NullPointerException;

@safe:

/// Determines whether an entity has yet to be persisted.
interface IsNewStrategy
{
    /// Whether `entity` is new.
    bool isNew(Object entity);
}

/// A strategy that leaves the decision to the entity's Persistable contract.
final class PersistableIsNewStrategy : IsNewStrategy
{
    package(flint) this() pure nothrow @nogc
    {
    }

    /// The shared strategy.
    static PersistableIsNewStrategy INSTANCE() nothrow @nogc
    {
        return statelessInstance!PersistableIsNewStrategy();
    }

    /// The name of the enum constant.
    string name() pure nothrow @nogc
    {
        return "INSTANCE";
    }

    /// The zero-based ordinal of the enum constant.
    int ordinal() pure nothrow @nogc
    {
        return 0;
    }

    override string toString() pure nothrow @nogc
    {
        return name();
    }

    /// The constants, in declaration order.
    static PersistableIsNewStrategy[] values()
    {
        return [INSTANCE];
    }

    /// The constant by its exact name.
    static PersistableIsNewStrategy valueOf(string constant)
    {
        if (constant is null)
            throw new NullPointerException("Name is null");
        if (constant != "INSTANCE")
        {
            enum prefix = "No enum constant org.springframework.data.support.PersistableIsNewStrategy.";
            throw new IllegalArgumentException(prefix ~ constant);
        }
        return INSTANCE;
    }

    override bool isNew(Object entity)
    {
        if (entity is null)
            throw new IllegalArgumentException("Entity must not be null");
        auto persistable = cast(PersistableState) entity;
        if (persistable is null)
        {
            const type = typeid(entity).name;
            throw new IllegalArgumentException("Given object of type " ~ type ~ " does not implement Persistable");
        }
        return persistable.isNew();
    }
}
