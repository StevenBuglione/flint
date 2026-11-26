// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/mapping/model/EntityInstantiatorIntegrationTests.java
// Copyright 2023-present the original author or authors.
// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/mapping/model/ReflectionEntityInstantiatorUnitTests.java
// ReflectionEntityInstantiatorUnitTests: Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module entity_instantiator_tests;

import flint.data.annotation : Transient;
import flint.data.core : TypeInformation;
import flint.data.mapping : InstanceCreatorMetadata, Parameter, PersistentEntity, PersistentProperty;
import flint.data.mapping.model : BasicPersistentEntity, EntityInstantiators,
    MappingInstantiationException, ParameterValueProvider, PersistentEntityParameterValueProvider;
import flint.engine.aot.any : Any, AnyTypeException;
import flint.engine.aot.descriptor : ConstructorDescriptor, DescriptorTable, ParameterDescriptor,
    PropertyDescriptor, descriptorOf, findAnnotation;
import flint.java.classref : ClassRef, classOf;
import flint.java.lang : IllegalStateException;
import flint.java.util : List;
import std.algorithm.searching : canFind;
import std.exception : collectException;
import std.typecons : Nullable;

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
    auto constructor = ConstructorDescriptor([
        ParameterDescriptor("foo", classOf!string.name), ParameterDescriptor("bar", classOf!int.name)
    ], invoke: invoke, canonical: canonical);
    return registeredEntity!T(constructor, DescriptorTable.withBuiltins());
}

private PersistentEntity!(T, ConstructorProperty) registeredEntity(T)(ConstructorDescriptor constructor,
        DescriptorTable table)
{
    auto descriptor = descriptorOf!T();
    descriptor.constructors = [constructor];
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
    auto selected = entity.getInstanceCreatorMetadata();
    auto instantiator = new EntityInstantiators().getInstantiatorFor(entity);
    auto error = collectException!MappingInstantiationException(instantiator.createInstance(entity, valuesFor(entity)));
    assert(error !is null && error.getEntityType() == classOf!WithTransientProperty);
    InstanceCreatorMetadata!() creator = error.getEntityCreator();
    assert(creator is selected);
    assert(creator.hasParameters() && creator.getParameterCount() == selected.getParameters().size());
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
    assert(error.getEntityCreator() is entity.getInstanceCreatorMetadata());
    assert(error.getConstructorArguments().isEmpty());
}

@("explicit diagnostics retain available creator metadata")
unittest
{
    auto arguments = List!Any.of(Any.of(1));
    auto cause = new IllegalStateException("bad arguments");
    auto entity = registeredEntity!WithTransientProperty(null);
    auto withEntity = new MappingInstantiationException(entity, arguments, cause);
    assert(withEntity.getEntityCreator() is entity.getInstanceCreatorMetadata());
    assert(withEntity.getConstructorArguments() is arguments && withEntity.getCause() is cause);

    auto withoutEntity = new MappingInstantiationException(arguments, cause);
    assert(withoutEntity.getEntityType().name is null && withoutEntity.getEntityCreator() is null);
}

private final class DiagnosticSample
{
    Nullable!long id;
    string name;

    this(Nullable!long id, string name)
    {
        this.id = id;
        this.name = name;
    }
}

private Any invokeDiagnosticSample(scope Any[] arguments)
{
    return Any.of(new DiagnosticSample(arguments[0].get!(Nullable!long), arguments[1].get!string));
}

private final class IncompatibleValues : ParameterValueProvider!(DiagnosticSample, ConstructorProperty)
{
    override Any getParameterValue(Parameter!(DiagnosticSample, ConstructorProperty))
    {
        return Any.of("FOO");
    }
}

@("capturesContextOnInstantiationException")
unittest
{
    auto table = DescriptorTable.withBuiltins();
    table.add(descriptorOf!(Nullable!long)());
    auto constructor = ConstructorDescriptor([
        ParameterDescriptor("id", classOf!(Nullable!long).name),
        ParameterDescriptor("name", classOf!string.name)
    ], invoke: &invokeDiagnosticSample);
    auto entity = registeredEntity!DiagnosticSample(constructor, table);
    auto instantiator = new EntityInstantiators().getInstantiatorFor(entity);
    auto error = collectException!MappingInstantiationException(instantiator.createInstance(entity,
            new IncompatibleValues));
    assert(error !is null && error.getEntityType() == classOf!DiagnosticSample);
    assert(error.getEntityCreator() is entity.getInstanceCreatorMetadata());
    assert(cast(AnyTypeException) error.getCause() !is null);
    assert(error.getConstructorArguments().toArray() == [Any.of("FOO"), Any.of("FOO")]);
    assert(error.msg.canFind(classOf!DiagnosticSample.name) && error.msg.canFind("FOO"));
    const signature = classOf!DiagnosticSample.name ~ "(" ~ classOf!(Nullable!long)
        .name ~ ", " ~ classOf!string.name ~ ")";
    assert(error.msg.canFind(signature));
}
