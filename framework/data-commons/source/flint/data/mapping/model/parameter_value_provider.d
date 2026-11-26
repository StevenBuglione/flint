// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/mapping/model/{ParameterValueProvider,PersistentEntityParameterValueProvider,PropertyValueProvider}.java
// ParameterValueProvider: Copyright 2011-present the original author or authors.
// PersistentEntityParameterValueProvider and PropertyValueProvider: Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.mapping.model.parameter_value_provider;

import flint.data.mapping : MappingException, Parameter, PersistentEntity, PersistentProperty;
import flint.engine.aot.any : Any;
import flint.java.classref : ClassRef, classOf;
import flint.java.lang : IllegalArgumentException, NullPointerException;
import std.meta : AliasSeq;
import std.typecons : Nullable;

@safe:

/// Supplies a value for a persistent property (R23).
interface PropertyValueProvider(P) if (is(P : PersistentProperty!P))
{
    /// The value of the property, or Any.init when absent.
    Any getPropertyValue(P property);
}

/// Supplies values for parameters of an entity creator (D-DATA-24).
interface ParameterValueProvider(T, P) if (is(P : PersistentProperty!P))
{
    /// The value to pass for the parameter, or Any.init when absent.
    Any getParameterValue(Parameter!(T, P) parameter);

    /// The zero value of a supported primitive type, or Any.init for a reference type.
    static Any getDefaultValue(ClassRef parameterType)
    {
        return parameterDefault(parameterType);
    }
}

/// Resolves creator parameters against an entity's registered persistent properties.
class PersistentEntityParameterValueProvider(T, P) : ParameterValueProvider!(T, P)
        if (is(P : PersistentProperty!P))
{
    private PersistentEntity!(T, P) entity;
    private Any delegate(P) @safe propertyValue;
    private Any parent;

    /// Uses the given property provider and optional parent.
    this(PersistentEntity!(T, P) entity, PropertyValueProvider!P provider, Any parent)
    {
        this(entity, provider is null ? null : &provider.getPropertyValue, parent);
    }

    /// Uses the given property callback and optional parent (R9).
    this(PersistentEntity!(T, P) entity, Any delegate(P) @safe provider, Any parent)
    {
        if (entity is null || provider is null)
            throw new NullPointerException("Entity and property value provider must not be null");
        this.entity = entity;
        this.propertyValue = provider;
        this.parent = parent;
    }

    override Any getParameterValue(Parameter!(T, P) parameter)
    {
        if (parameter is null)
            throw new NullPointerException("Parameter must not be null");
        auto creator = entity.getInstanceCreatorMetadata();
        if (creator !is null && creator.isParentParameter(parameter))
            return parent;
        if (parameter.isTransient())
            return parameterDefault(parameter.getRawType());

        const name = parameter.getName();
        if (name.isNull)
        {
            const message = "Parameter " ~ parameter.getRawType().name ~ " does not have a name";
            throw new MappingException(Nullable!string(message));
        }
        auto property = entity.getPersistentProperty(name.get);
        if (property is null)
        {
            const message = "No property " ~ name.get ~ " found on entity " ~ entity.getType()
                .name ~ " to bind constructor parameter to";
            throw new MappingException(Nullable!string(message));
        }
        return propertyValue(property);
    }
}

private Any parameterDefault(ClassRef parameterType)
{
    if (parameterType.name is null)
        throw new NullPointerException("Parameter type must not be null");
    static foreach (T; AliasSeq!(bool, byte, short, int, long, float, double, char, wchar, dchar))
    {
        if (parameterType.name == classOf!T.name)
            return Any.of(cast(T) 0);
    }
    if (parameterType.name == classOf!void.name)
        throw new IllegalArgumentException("Primitive type void not supported");
    return Any.init;
}
