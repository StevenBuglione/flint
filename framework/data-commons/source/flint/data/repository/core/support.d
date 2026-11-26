// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/repository/core/support/{AbstractEntityInformation,DelegatingEntityInformation}.java
// AbstractEntityInformation: Copyright 2011-present the original author or authors.
// DelegatingEntityInformation: Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.repository.core.support;

import flint.data.domain.persistable : NullableId;
import flint.data.repository.core : EntityInformation;
import flint.java.classref : ClassRef, classOf;
import flint.java.lang : IllegalArgumentException;

@safe:

/// An EntityInformation that forwards metadata and state to another instance.
class DelegatingEntityInformation(T, ID) : EntityInformation!(T, ID)
{
    private EntityInformation!(T, ID) delegateInformation;

    /// Wraps the supplied metadata.
    this(EntityInformation!(T, ID) delegateInformation)
    {
        this.delegateInformation = delegateInformation;
    }

    mixin EntityInformation!(T, ID).Defaults;

    override ClassRef getJavaType()
    {
        return delegateInformation.getJavaType();
    }

    override bool isNew(T entity)
    {
        return delegateInformation.isNew(entity);
    }

    override NullableId!ID getId(T entity)
    {
        return delegateInformation.getId(entity);
    }

    override ClassRef getIdType()
    {
        return delegateInformation.getIdType();
    }
}

/// Determines newness from an absent identifier or a primitive numeric identifier whose Java long value is zero.
abstract class AbstractEntityInformation(T, ID) : EntityInformation!(T, ID)
{
    mixin EntityInformation!(T, ID).Defaults;

    /// Captures the domain class through the type parameter (R4).
    this()
    {
    }

    override bool isNew(T entity)
    {
        auto id = getId(entity);
        const idType = getIdType();
        static if (is(ID == class) || is(ID == interface))
        {
            return isNewIdentifier(idType, id is null);
        }
        else
        {
            const missing = id.isNull;
            static if (is(ID == byte) || is(ID == short) || is(ID == int) || is(ID == long))
            {
                if (!missing)
                    return isNewIdentifier(idType, false, true, id.get == 0);
            }
            else static if (is(ID == float) || is(ID == double))
            {
                if (!missing)
                {
                    const value = id.get;
                    // Java Number.longValue truncates toward zero and converts NaN to zero.
                    return isNewIdentifier(idType, false, true, !(value <= -1 || value >= 1));
                }
            }
            return isNewIdentifier(idType, missing);
        }
    }

    override ClassRef getJavaType()
    {
        return classOf!T;
    }
}

private bool isNewIdentifier(ClassRef idType, bool missing, bool numeric = false, bool zero = false)
{
    string name = idType.name;
    switch (name)
    {
    case classOf!byte.name:
    case classOf!short.name:
    case classOf!int.name:
    case classOf!long.name:
    case classOf!float.name:
    case classOf!double.name:
        if (numeric)
            return zero;
        break;
    case classOf!bool.name:
        name = "boolean";
        break;
    case classOf!char.name:
    case classOf!wchar.name:
    case classOf!dchar.name:
        name = "char";
        break;
    default:
        return missing;
    }
    throw new IllegalArgumentException("Unsupported primitive id type " ~ name);
}
