// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/mapping/model/AbstractPersistentProperty.java
// Copyright 2011-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.mapping.model.abstract_persistent_property;

import flint.data.core : TypeInformation;
import flint.data.mapping : PersistentEntity, PersistentProperty;
import flint.java.classref : ClassRef;
import flint.java.lang : IllegalArgumentException;

@safe:

/// Persistent property metadata derived from the declaring entity (D-DATA-28).
abstract class AbstractPersistentProperty(P) : PersistentProperty!P
{
    private const string name;
    private PersistentEntity!() owner;
    private TypeInformation information;

    /// Resolves the named property in the owning entity's registered type information.
    protected this(string name, PersistentEntity!() owner)
    {
        if (owner is null)
            throw new IllegalArgumentException("Owner entity must not be null");

        this.name = name;
        this.owner = owner;
        information = owner.getTypeInformation().getRequiredProperty(name);
    }

    /// The entity that declares this property.
    PersistentEntity!() getOwner()
    {
        return owner;
    }

    override string getName()
    {
        return name;
    }

    override ClassRef getType()
    {
        return information.getType();
    }

    /// The resolved declaration, including component and map types.
    TypeInformation getTypeInformation()
    {
        return information;
    }

    /// A map key or collection element type, or ClassRef.init for a scalar.
    ClassRef getComponentType()
    {
        return information.isMap() || information.isCollectionLike()
            ? information.getRequiredComponentType().getType() : ClassRef.init;
    }

    /// A scalar's declared type, a collection element type, or a map value type.
    ClassRef getActualType()
    {
        return getActualTypeInformation().getType();
    }

    /// Resolves the actual type from the registered property declaration.
    protected TypeInformation getActualTypeInformation()
    {
        return information.getRequiredActualType();
    }
}
