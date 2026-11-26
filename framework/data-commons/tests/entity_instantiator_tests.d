// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/mapping/model/EntityInstantiatorIntegrationTests.java
// Copyright 2023-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module entity_instantiator_tests;

import flint.data.annotation : Transient;
import flint.data.core : TypeInformation;
import flint.data.mapping : PersistentEntity, PersistentProperty;
import flint.data.mapping.model : BasicPersistentEntity, EntityInstantiators,
    MappingInstantiationException, PersistentEntityParameterValueProvider;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : ConstructorDescriptor, DescriptorTable, ParameterDescriptor,
    PropertyDescriptor, descriptorOf, findAnnotation;
import flint.java.classref : ClassRef, classOf;
import flint.java.lang : IllegalStateException;
import std.exception : collectException;

@safe:

private final class ConstructorProperty : PersistentProperty!ConstructorProperty
{
    private string name;
    private ClassRef type;
    private bool transient_;

    this(const PropertyDescriptor property)
    {
        name = property.name;
        type = ClassRef(property.type);
        transient_ = findAnnotation(property.annotations, classOf!Transient.name) !is null;
    }

    override string getName()
    {
        return name;
    }

    override ClassRef getType()
    {
        return type;
    }

    override bool isIdProperty()
    {
        return false;
    }

    override bool isVersionProperty()
    {
        return false;
    }

    override bool isTransient()
    {
        return transient_;
    }

    override bool isAssociation()
    {
        return false;
    }
}

private final class WithTransientProperty
{
    @Transient
    string foo;
    @Transient
    int bar;

    this(string foo, int bar)
    {
        this.foo = foo;
        this.bar = bar;
    }
}

private struct RecordWithTransientProperty
{
    @Transient
    string foo;
    @Transient
    int bar;
}

private alias Invoke = Any function(scope Any[] arguments) @safe;

private PersistentEntity!(T, ConstructorProperty) registeredEntity(T)(Invoke invoke, bool canonical = false)
{
    auto descriptor = descriptorOf!T();
    descriptor.constructors = [
        ConstructorDescriptor([
            ParameterDescriptor("foo", classOf!string.name),
            ParameterDescriptor("bar", classOf!int.name)
        ], invoke: invoke, canonical: canonical)
    ];
    auto table = DescriptorTable.withBuiltins();
    table.add(descriptor);
    auto entity = new BasicPersistentEntity!(T, ConstructorProperty)(TypeInformation.of!T(table));
    foreach (ref property; descriptor.properties)
        entity.addPersistentProperty(new ConstructorProperty(property));
    return entity;
}

private PersistentEntityParameterValueProvider!(T, ConstructorProperty) valuesFor(T)(
        PersistentEntity!(T, ConstructorProperty) entity)
{
    auto unexpected = delegate Any(ConstructorProperty property) @safe {
        assert(property !is null);
        throw new IllegalStateException("Transient parameters must bypass property lookup");
    };
    return new PersistentEntityParameterValueProvider!(T, ConstructorProperty)(entity, unexpected, Any.init);
}

private Any invokeClass(scope Any[] arguments)
{
    assert(arguments.length == 2 && arguments[0].isNull());
    return Any.of(new WithTransientProperty(null, arguments[1].get!int));
}

private Any invokeRecord(scope Any[] arguments)
{
    assert(arguments.length == 2 && arguments[0].isNull());
    return Any.of(RecordWithTransientProperty(null, arguments[1].get!int));
}

@("shouldDefaultTransientProperties")
unittest
{
    auto entity = registeredEntity!WithTransientProperty(&invokeClass);
    auto instantiator = new EntityInstantiators().getInstantiatorFor(entity);
    const result = instantiator.createInstance(entity, valuesFor(entity));
    assert(result.foo is null && result.bar == 0);
}

@("shouldDefaultTransientRecordProperties")
unittest
{
    auto entity = registeredEntity!RecordWithTransientProperty(&invokeRecord, true);
    auto instantiator = new EntityInstantiators().getInstantiatorFor(entity);
    const result = instantiator.createInstance(entity, valuesFor(entity));
    assert(result.foo is null && result.bar == 0);
}

private Any failInvocation(scope Any[])
{
    throw new IllegalStateException("constructor rejected its arguments");
}

@("constructor failure preserves the cause and ordered arguments")
unittest
{
    auto entity = registeredEntity!WithTransientProperty(&failInvocation);
    auto instantiator = new EntityInstantiators().getInstantiatorFor(entity);
    auto error = collectException!MappingInstantiationException(instantiator.createInstance(entity, valuesFor(entity)));
    assert(error !is null && error.getEntityType() == classOf!WithTransientProperty);
    const cause = cast(IllegalStateException) error.getCause();
    assert(cause !is null && cause.msg == "constructor rejected its arguments");
    auto arguments = error.getConstructorArguments();
    assert(arguments.size() == 2 && arguments.get(0).isNull() && arguments.get(1).get!int == 0);
}

@("selected constructors require a registered invocation callback")
unittest
{
    auto entity = registeredEntity!WithTransientProperty(null);
    auto instantiator = new EntityInstantiators().getInstantiatorFor(entity);
    auto error = collectException!MappingInstantiationException(instantiator.createInstance(entity, valuesFor(entity)));
    assert(error !is null && error.getEntityType() == classOf!WithTransientProperty);
    assert(error.getConstructorArguments().isEmpty());
}
