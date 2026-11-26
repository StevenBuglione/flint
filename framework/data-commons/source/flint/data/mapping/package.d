// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/mapping/{IdentifierAccessor,MappingException,PersistentEntity,PersistentProperty,TargetAwareIdentifierAccessor}.java
// IdentifierAccessor: Copyright 2014-present the original author or authors.
// MappingException, PersistentEntity and PersistentProperty: Copyright 2011-present the original author or authors.
// TargetAwareIdentifierAccessor: Copyright 2017-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.mapping;

import flint.data.core : TypeInformation;
import flint.engine.aot.any : Any;
import flint.java.classref : ClassRef;
import flint.java.lang : IllegalStateException, Iterable, RuntimeException, String;
import std.typecons : Nullable;

@safe:

/// Access to the identifier of an entity.
interface IdentifierAccessor
{
    /// The identifier or a null value when the entity has none.
    Any getIdentifier();

    /// The identifier, or an IllegalStateException if it is absent.
    Any getRequiredIdentifier();

    /// Default missing-identifier check for implementations (R3).
    mixin template Defaults()
    {
        imported!"flint.engine.aot.any".Any getRequiredIdentifier()
        {
            auto identifier = getIdentifier();
            if (identifier.isNull())
                throw new imported!"flint.java.lang".IllegalStateException("Could not obtain identifier");
            return identifier;
        }
    }
}

/// Adds the target's rendering to an absent-identifier error.
abstract class TargetAwareIdentifierAccessor : IdentifierAccessor
{
    private Any target;

    /// Captures the target for a missing-identifier diagnostic.
    this(Any target)
    {
        this.target = target;
    }

    override Any getRequiredIdentifier()
    {
        auto identifier = getIdentifier();
        if (identifier.isNull())
            throw new IllegalStateException(String.format("Could not obtain identifier from %s", target));
        return identifier;
    }
}

/// Reports a failure in persistence mapping.
class MappingException : RuntimeException
{
    /// Constructs the exception with an optional detail message.
    this(Nullable!string message) pure nothrow
    {
        super(message.isNull ? null : message.get);
    }

    /// Constructs the exception with an optional detail message and an initialized cause.
    this(Nullable!string message, Throwable cause)
    {
        super(message.isNull ? null : message.get, cause);
        // The two-argument Java constructor initializes even a null cause.
        if (cause is null)
            super.initCause(null);
    }
}

package(flint.data) interface PersistentPropertyType
{
    ClassRef getType();
}

/// Describes a property of a persistent entity.
interface PersistentProperty(P) : PersistentPropertyType
{
    /// The name of this property.
    string getName();
}

// The repository adapter uses the same metadata without retaining the property type parameter.
package(flint.data) interface PersistentEntityIdentity
{
    ClassRef getType();
    PersistentPropertyType getRequiredIdProperty();
    IdentifierAccessor getIdentifierAccessor(Any bean);
    bool isNew(Any bean);
}

/// Metadata for the persistent properties of a domain entity.
interface PersistentEntity(T, P) : PersistentEntityIdentity, Iterable!P if (is(P : PersistentProperty!P))
{
    /// The entity's qualified name.
    string getName();

    /// The identifier property, or null when no identifier is mapped.
    P getIdProperty();

    /// The identifier property, or an IllegalStateException when no identifier is mapped.
    override P getRequiredIdProperty();

    /// Whether the entity has an identifier property.
    bool hasIdProperty();

    /// The metadata for the entity's domain type.
    TypeInformation getTypeInformation();

    /// Supplies the default required-identifier property check (R3).
    mixin template Defaults(PropertyType = P)
    {
        PropertyType getRequiredIdProperty()
        {
            auto identifier = getIdProperty();
            if (identifier is null)
                throw new imported!"flint.java.lang".IllegalStateException(
                        "Required identifier property not found for " ~ getType().name);
            return identifier;
        }
    }
}
