// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/mapping/ParameterUnitTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module parameter_tests;

import flint.beans.factory.annotation : Value;
import flint.data.annotation : PersistenceCreator, Transient;
import flint.data.core : TypeInformation;
import flint.data.mapping : Parameter, PersistentEntity, PersistentProperty;
import flint.data.mapping.model : BasicPersistentEntity;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : ConstructorDescriptor, DescriptorTable, MergedAnnotation,
    ParameterDescriptor, descriptorOf;
import flint.java.classref : ClassRef, classOf;
import flint.java.lang : IllegalArgumentException, IllegalStateException, UnsupportedOperationException;
import std.exception : assertThrown, collectException;
import std.typecons : Nullable;

@safe:

private final class Document
{
    long revision;
}

private final class RevisionProperty : PersistentProperty!RevisionProperty
{
    private bool transient_;

    this(bool transient_ = true)
    {
        this.transient_ = transient_;
    }

    override string getName()
    {
        return "revision";
    }

    override ClassRef getType()
    {
        return classOf!long;
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

private PersistentEntity!(Document, RevisionProperty) withConstructors(DescriptorTable descriptors,
        ConstructorDescriptor[] constructors)
{
    auto descriptor = descriptorOf!Document();
    descriptor.constructors = constructors;
    descriptors.add(descriptor);
    auto entity = new BasicPersistentEntity!(Document, RevisionProperty)(TypeInformation.of!Document(descriptors));
    entity.addPersistentProperty(new RevisionProperty(false));
    return entity;
}

private alias CreatorParameter = Parameter!(Document, RevisionProperty);

private CreatorParameter parameter(Nullable!string name)
{
    return new CreatorParameter(name, TypeInformation.of!long(DescriptorTable.withBuiltins()), null, null);
}

@("getRequiredNameDoesNotThrowExceptionWhenHasName")
unittest
{
    assert(parameter(Nullable!string("someName")).getRequiredName() == "someName");
}

@("getRequiredNameThrowsExceptionWhenHasNoName")
unittest
{
    const error = collectException!IllegalStateException(parameter(Nullable!string.init).getRequiredName());
    assert(error !is null && error.msg == "No name associated with this parameter");
}

@("hasNameReturnsTrueWhenHasName")
unittest
{
    assert(parameter(Nullable!string("someName")).hasName());
    assert(parameter(Nullable!string("")).hasName());
}

@("hasNameReturnsFalseWhenHasNoName")
unittest
{
    auto unnamed = parameter(Nullable!string.init);
    assert(!unnamed.hasName() && unnamed.getName().isNull);
}

@("parameter reads annotation metadata from a constructor descriptor")
unittest
{
    auto recorded = ParameterDescriptor("revision", classOf!long.name, [
        MergedAnnotation(classOf!Value.name, Any.of(Value("${record.revision:1}"))),
        MergedAnnotation(classOf!Transient.name, Any.of(Transient.init)),
    ]);
    auto type = TypeInformation.of!long(DescriptorTable.withBuiltins());
    auto value = new CreatorParameter(Nullable!string(recorded.name), type, recorded.annotations, null);
    assert(value.getType() is type && value.getRawType() == ClassRef(recorded.type));
    assert(value.getAnnotations().isPresent!Value() && value.isTransient());
    assert(value.hasValueExpression() && value.getRequiredValueExpression() == "${record.revision:1}");
    assert(value.getSpelExpression() == value.getValueExpression());
}

@("parameter recognizes only text expressions and the registered transient property")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    descriptors.add(descriptorOf!Document());
    auto entity = new BasicPersistentEntity!(Document, RevisionProperty)(TypeInformation.of!Document(descriptors));
    entity.addPersistentProperty(new RevisionProperty);
    auto type = TypeInformation.of!long(descriptors);
    auto value = new CreatorParameter(Nullable!string("revision"), type,
            [MergedAnnotation(classOf!Value.name, Any.of(Value("\u2003\t")))], entity);
    assert(value.isTransient() && !value.hasValueExpression() && value.getValueExpression().isNull);
    assertThrown!IllegalStateException(value.getRequiredValueExpression());
    assertThrown!IllegalArgumentException(new CreatorParameter(Nullable!string.init, null, null, null));
}

@("registered creator metadata preserves parameter order and property membership")
unittest
{
    auto selected = ConstructorDescriptor([
        ParameterDescriptor("revision", classOf!long.name),
        ParameterDescriptor("tag", classOf!string.name, [
            MergedAnnotation(classOf!Value.name, Any.of(Value("registered")))
        ]),
    ], [MergedAnnotation(classOf!PersistenceCreator.name, Any.of(PersistenceCreator.init))]);
    auto canonical = ConstructorDescriptor([ParameterDescriptor("revision", classOf!long.name)], canonical: true);
    auto entity = withConstructors(DescriptorTable.withBuiltins(), [
        ConstructorDescriptor.init, canonical, selected
    ]);
    auto creator = entity.getInstanceCreatorMetadata();
    assert(creator !is null && creator is entity.getInstanceCreatorMetadata());
    assert(creator.hasParameters() && creator.getParameterCount() == 2);
    auto parameters = creator.getParameters();
    assert(parameters.get(0).getRequiredName() == "revision" && parameters.get(0).getRawType() == classOf!long);
    assert(parameters.get(1).getRequiredName() == "tag" && parameters.get(1).getRawType() == classOf!string);
    assert(parameters.get(1).getRequiredValueExpression() == "registered"
            && !creator.isParentParameter(parameters.get(1)));
    assertThrown!UnsupportedOperationException(parameters.clear());
    auto revision = entity.getRequiredPersistentProperty("revision");
    assert(creator.isCreatorParameter(revision) && entity.isCreatorArgument(revision));
    assert(!entity.isCreatorArgument(null) && !entity.isCreatorArgument(new RevisionProperty(false)));
}

@("creator selection distinguishes canonical, default, sole and ambiguous constructors")
unittest
{
    ParameterDescriptor[] revision = [ParameterDescriptor("revision", classOf!long.name)];
    auto canonical = ConstructorDescriptor(revision, canonical: true);
    auto primary = ConstructorDescriptor(revision);
    auto alternative = ConstructorDescriptor([ParameterDescriptor("tag", classOf!string.name)]);
    auto noArguments = ConstructorDescriptor.init;
    auto descriptors = DescriptorTable.withBuiltins();
    assert(withConstructors(descriptors, [noArguments, canonical]).getInstanceCreatorMetadata().hasParameters());
    assert(!withConstructors(descriptors, [primary, noArguments]).getInstanceCreatorMetadata().hasParameters());
    assert(withConstructors(descriptors, [primary]).getInstanceCreatorMetadata().getParameterCount() == 1);
    assert(withConstructors(descriptors, [primary, alternative]).getInstanceCreatorMetadata() is null);
    assert(withConstructors(descriptors, null).getInstanceCreatorMetadata() is null);
}

private final class LateParameterType
{
}

@("creator metadata can be retried after registering a missing parameter type")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    auto entity = withConstructors(descriptors,
            [ConstructorDescriptor([ParameterDescriptor("extra", classOf!LateParameterType.name)])]);
    assertThrown!IllegalStateException(entity.getInstanceCreatorMetadata());
    descriptors.add(descriptorOf!LateParameterType());
    assert(entity.getInstanceCreatorMetadata().getParameters().get(0).getRawType() == classOf!LateParameterType);
}
