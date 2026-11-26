// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/annotation
// Copyright 2011-present the original author or authors.
// CreatedBy, CreatedDate, LastModifiedBy, LastModifiedDate, Version: Copyright 2012-present the original author or authors.
// QueryAnnotation: Copyright 2013-present the original author or authors.
// AccessType and ReadOnlyProperty: Copyright 2014-present the original author or authors.
// Immutable: Copyright 2018-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.annotation;

import flint.core.annotation : AliasFor;
import flint.java.classref : ClassRef;

@safe:

/// Select field or property access for a persistent type or member.
struct AccessType
{
    /// The supported ways to access a property.
    enum Type
    {
        FIELD,
        PROPERTY,
    }

    /// The selected access strategy.
    Type value;
}

/// Identifies the actor that created an entity.
struct CreatedBy
{
}

/// Records when an entity was created.
struct CreatedDate
{
}

/// Identifies the persistent entity ID.
struct Id
{
}

/// Marks a type whose persistent values cannot be mutated.
struct Immutable
{
}

/// Identifies the actor that last modified an entity.
struct LastModifiedBy
{
}

/// Records when an entity was last modified.
struct LastModifiedDate
{
}

/// Selects a constructor or factory method for reconstructing a persistent object.
struct PersistenceCreator
{
}

/// Marks a persistent type, field or parameter.
struct Persistent
{
}

/// Meta-annotation for annotations that declare repository queries.
struct QueryAnnotation
{
}

/// Includes a property when reading and omits it when writing.
struct ReadOnlyProperty
{
}

/// Marks a reference to another persistent object.
struct Reference
{
    /// The reference's target type. An empty token requests type inference (R4).
    @AliasFor(attribute: "to")
    ClassRef value;

    /// Alias for `value`.
    @AliasFor(attribute: "value")
    ClassRef to;
}

/// Exclude a field from persistent property mapping.
struct Transient
{
}

/// The name used to represent this persistent type in a store.
@Persistent
struct TypeAlias
{
    /// The alias used in place of the type name.
    string value;
}

/// Identifies the property used for optimistic locking.
struct Version
{
}
