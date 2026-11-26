// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/mapping/model/{EntityInstantiator,EntityInstantiators,MappingInstantiationException}.java
// EntityInstantiator and EntityInstantiators: Copyright 2012-present the original author or authors.
// MappingInstantiationException: Copyright 2011-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.mapping.model.entity_instantiator;

import flint.beans : BeanInstantiationException;
import flint.data.core.type_information : registeredDescriptor;
import flint.data.mapping : InstanceCreatorMetadata, PersistentEntity, PersistentProperty, PreferredConstructor;
import flint.data.mapping.model.parameter_value_provider : ParameterValueProvider;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : ConstructorDescriptor;
import flint.engine.aot.objects : statelessInstance;
import flint.java.classref : ClassRef;
import flint.java.lang : IllegalArgumentException, IllegalStateException, RuntimeException;
import flint.java.util : ArrayList, Collections, List, Map;

@safe:

/// Wildcard view of an instantiator for a registry of heterogeneous types (D-DATA-25).
interface EntityInstantiator()
{
}

/// Constructs an entity from a source of creator parameter values (D-DATA-25).
interface EntityInstantiator(T, P) : EntityInstantiator!() if (is(P : PersistentProperty!P))
{
    /// Invokes the creator of the given entity using the supplied values.
    T createInstance(PersistentEntity!(T, P) entity, ParameterValueProvider!(T, P) provider);
}

/// Supplies an exact type match or the fallback instantiator.
class EntityInstantiators
{
    private EntityInstantiator!() fallback;
    private EntityInstantiator!() delegate(ClassRef) @safe lookupCustom;

    /// Uses the registered constructor strategy when no custom strategy is selected.
    this()
    {
    }

    /// Uses a custom fallback.
    this(EntityInstantiator!() fallback)
    {
        if (fallback is null)
            throw new IllegalArgumentException("DefaultInstantiator must not be null");
        this.fallback = fallback;
    }

    /// Uses the registered constructor strategy for types absent from the custom map.
    this(M)(M customInstantiators) if (is(M : Map!(ClassRef, EntityInstantiator!())))
    {
        setCustomInstantiators(customInstantiators);
    }

    /// Uses the custom fallback for types absent from the custom map.
    this(M)(EntityInstantiator!() fallback, M customInstantiators)
            if (is(M : Map!(ClassRef, EntityInstantiator!())))
    {
        this(fallback);
        setCustomInstantiators(customInstantiators);
    }

    /// Finds the strategy for the entity's exact type and checks its entity/property binding.
    EntityInstantiator!(T, P) getInstantiatorFor(T, P)(PersistentEntity!(T, P) entity)
            if (is(P : PersistentProperty!P))
    {
        if (entity is null)
            throw new IllegalArgumentException("Entity must not be null");
        const type = entity.getType();
        return bindInstantiator!(T, P)(findCustomOrFallback(type), type);
    }

    private static EntityInstantiator!(T, P) bindInstantiator(T, P)(EntityInstantiator!() selected, ClassRef type)
    {
        if (selected is null)
            return statelessInstance!(RegisteredEntityInstantiator!(T, P))();
        if (auto typed = cast(EntityInstantiator!(T, P)) selected)
            return typed;
        throw new IllegalArgumentException("Incompatible EntityInstantiator binding for " ~ type.name);
    }

    private EntityInstantiator!() findCustomOrFallback(ClassRef type)
    {
        auto custom = lookupCustom is null ? null : lookupCustom(type);
        return custom is null ? fallback : custom;
    }

    private void setCustomInstantiators(M)(M customInstantiators)
    {
        if (customInstantiators is null)
            throw new IllegalArgumentException("CustomInstantiators must not be null");
        lookupCustom = &(cast(Map!(ClassRef, EntityInstantiator!())) customInstantiators).get;
    }
}

/// Reports a failed attempt to construct an entity, including the supplied arguments and cause.
class MappingInstantiationException : RuntimeException
{
    private ClassRef entityType;
    private InstanceCreatorMetadata!() entityCreator;
    private List!Any constructorArguments;

    /// Reports a failure for an entity with registered type metadata.
    this(T, P)(PersistentEntity!(T, P) entity, List!Any arguments, Exception cause)
    {
        auto metadata = entity is null ? null : entity.getInstanceCreatorMetadata();
        auto creator = cast(PreferredConstructor!(T, P)) metadata;
        const descriptor = creator is null ? ConstructorDescriptor.init : creator.getConstructor();
        this(entity is null ? ClassRef.init : entity.getType(), metadata, creator is null
                ? null : &descriptor, arguments, cause);
    }

    /// Reports a failure without an entity type.
    this(List!Any arguments, Exception cause)
    {
        this(ClassRef.init, null, null, arguments, cause);
    }

    private this(ClassRef entityType, InstanceCreatorMetadata!() entityCreator,
            scope const(ConstructorDescriptor)* constructor, List!Any arguments, Exception cause)
    {
        super(instantiationMessage(entityType, constructor, arguments), cause);
        this.entityType = entityType;
        this.entityCreator = entityCreator;
        this.constructorArguments = arguments;
    }

    /// The entity type, or ClassRef.init if absent.
    ClassRef getEntityType()
    {
        return entityType;
    }

    /// The creator selected for the attempt, or null if unavailable.
    InstanceCreatorMetadata!() getEntityCreator()
    {
        return entityCreator;
    }

    /// The arguments supplied to the constructor in parameter order.
    List!Any getConstructorArguments()
    {
        return constructorArguments;
    }
}

private string instantiationMessage(ClassRef entityType,
        scope const(ConstructorDescriptor)* constructor, List!Any arguments)
{
    if (entityType.name is null)
        return null;

    char[] message;
    message ~= "Failed to instantiate ";
    message ~= entityType.name;
    message ~= " using constructor ";
    if (constructor is null)
        message ~= "NO_CONSTRUCTOR";
    else
    {
        message ~= entityType.name;
        message ~= '(';
        foreach (index, ref parameter; constructor.parameters)
        {
            if (index != 0)
                message ~= ", ";
            message ~= parameter.type;
        }
        message ~= ')';
    }
    message ~= " with arguments ";
    message ~= arguments.toString();
    return message.idup;
}

private final class RegisteredEntityInstantiator(T, P) : EntityInstantiator!(T, P)
{
    override T createInstance(PersistentEntity!(T, P) entity, ParameterValueProvider!(T, P) provider)
    {
        if (entity is null || provider is null)
            throw new IllegalArgumentException("Entity and parameter provider must not be null");

        auto metadata = entity.getInstanceCreatorMetadata();
        if (metadata is null)
            return createDefaultInstance(entity);

        auto creator = cast(PreferredConstructor!(T, P)) metadata;
        const descriptor = creator is null ? ConstructorDescriptor.init : creator.getConstructor();
        const invoke = descriptor.invoke;
        if (invoke is null)
        {
            const type = entity.getType();
            throw new MappingInstantiationException(type, metadata, creator is null ? null : &descriptor,
                    Collections.emptyList!Any(),
                    new IllegalStateException("No registered constructor invocation for " ~ type.name));
        }

        auto parameters = creator.getParameters();
        const count = parameters.size();
        auto arguments = new Any[count];
        foreach (index; 0 .. count)
            arguments[index] = provider.getParameterValue(parameters.get(index));

        try
        {
            return requireInstance!T(invoke(arguments));
        }
        catch (Exception cause)
        {
            throw new MappingInstantiationException(entity.getType(), metadata, &descriptor,
                    new ArrayList!Any(arguments), cause);
        }
    }
}

private T createDefaultInstance(T, P)(PersistentEntity!(T, P) entity)
{
    const type = entity.getType();
    const descriptor = registeredDescriptor(entity.getTypeInformation());
    if (descriptor is null || descriptor.create is null)
        throw defaultInstantiationFailure(type, "No registered default constructor");

    try
    {
        return requireInstance!T(descriptor.create());
    }
    catch (Exception cause)
    {
        throw defaultInstantiationFailure(type, "Default constructor failed", cause);
    }
}

private MappingInstantiationException defaultInstantiationFailure(ClassRef type, string message, Exception cause = null)
{
    auto failure = new BeanInstantiationException(type.name, message, cause);
    return new MappingInstantiationException(type, null, null, Collections.emptyList!Any(), failure);
}

private T requireInstance(T)(Any instance)
{
    if (instance.isNull())
        throw new IllegalStateException("Registered constructor returned no instance");
    return instance.get!T();
}
