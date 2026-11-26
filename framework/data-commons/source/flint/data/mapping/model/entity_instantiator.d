// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/mapping/model/{EntityInstantiator,EntityInstantiators,MappingInstantiationException}.java
// EntityInstantiator and EntityInstantiators: Copyright 2012-present the original author or authors.
// MappingInstantiationException: Copyright 2011-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.mapping.model.entity_instantiator;

import flint.data.mapping : InstanceCreatorMetadata, PersistentEntity, PersistentProperty, PreferredConstructor;
import flint.data.mapping.model.parameter_value_provider : ParameterValueProvider;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : ConstructorDescriptor;
import flint.engine.aot.objects : statelessInstance;
import flint.java.classref : ClassRef;
import flint.java.lang : IllegalArgumentException, IllegalStateException, RuntimeException;
import flint.java.util : ArrayList, Collections, List;

@safe:

/// Constructs an entity from a source of creator parameter values (D-DATA-25).
interface EntityInstantiator(T, P) if (is(P : PersistentProperty!P))
{
    /// Invokes the creator of the given entity using the supplied values.
    T createInstance(PersistentEntity!(T, P) entity, ParameterValueProvider!(T, P) provider);
}

/// Supplies the default instantiator for registered constructor metadata.
class EntityInstantiators
{
    /// Finds the stateless instantiator for the given entity and property type.
    EntityInstantiator!(T, P) getInstantiatorFor(T, P)(PersistentEntity!(T, P) entity)
            if (is(P : PersistentProperty!P))
    {
        if (entity is null)
            throw new IllegalArgumentException("Entity must not be null");
        return statelessInstance!(RegisteredEntityInstantiator!(T, P))();
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
            auto instance = invoke(arguments);
            if (instance.isNull())
                throw new IllegalStateException("Registered constructor returned no instance");
            return instance.get!T();
        }
        catch (Exception cause)
        {
            throw new MappingInstantiationException(entity.getType(), metadata, &descriptor,
                    new ArrayList!Any(arguments), cause);
        }
    }
}
