// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/mapping/{IdentifierAccessor,MappingException,TargetAwareIdentifierAccessor}.java
// IdentifierAccessor: Copyright 2014-present the original author or authors.
// MappingException: Copyright 2011-present the original author or authors.
// TargetAwareIdentifierAccessor: Copyright 2017-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.mapping;

import flint.engine.aot.any : Any;
import flint.java.lang : IllegalStateException, RuntimeException, String;
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
