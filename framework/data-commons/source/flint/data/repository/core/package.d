// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/repository/core/{EntityMetadata,EntityInformation}.java
// Copyright 2011-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.repository.core;

import flint.data.domain.persistable : NullableId;
import flint.java.classref : ClassRef;

@safe:

/// Metadata for an entity type.
interface EntityMetadata(T)
{
    /// The domain class token (R4).
    ClassRef getJavaType();
}

/// Access to the identifier and persistence state of an entity.
interface EntityInformation(T, ID) : EntityMetadata!T
{
    /// Whether the entity is considered new.
    bool isNew(T entity);

    /// The identifier, which can be absent (R5).
    NullableId!ID getId(T entity);

    /// The identifier, or an IllegalArgumentException if it is absent.
    ID getRequiredId(T entity);

    /// The identifier class token (R4).
    ClassRef getIdType();

    /// Default identifier validation for implementations (R3).
    mixin template Defaults(EntityType = T, IdentifierType = ID)
    {
        IdentifierType getRequiredId(EntityType entity)
        {
            import flint.java.lang : IllegalArgumentException, valueOf;

            static if (is(typeof(entity is null)))
            {
                if (entity is null)
                    throw new IllegalArgumentException("Entity must not be null");
            }

            auto identifier = (cast(EntityInformation!(EntityType, IdentifierType)) this).getId(entity);
            static if (is(IdentifierType == class) || is(IdentifierType == interface))
            {
                if (identifier !is null)
                    return identifier;
            }
            else
            {
                if (!identifier.isNull)
                    return identifier.get;
            }

            throw new IllegalArgumentException("Could not obtain required identifier from entity " ~ valueOf(entity));
        }
    }
}
