// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/domain/Persistable.java
// Copyright 2008-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.domain.persistable;

import std.typecons : Nullable;

@safe:

package(flint.data) interface PersistableState
{
    /// Whether the entity is new, independent of its identifier.
    bool isNew();
}

private template NullableId(ID)
{
    static if (is(ID == class) || is(ID == interface))
        alias NullableId = ID;
    else
        alias NullableId = Nullable!ID;
}

/// An entity that provides its identifier and determines whether it is new.
interface Persistable(ID) : PersistableState
{
    /// The identifier, which can be absent (R5).
    NullableId!ID getId();
}
