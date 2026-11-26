// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/mapping/ParameterUnitTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module parameter_tests;

import flint.beans.factory.annotation : Value;
import flint.data.annotation : Transient;
import flint.data.core : TypeInformation;
import flint.data.mapping : Parameter, PersistentProperty;
import flint.data.mapping.model : BasicPersistentEntity;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : DescriptorTable, MergedAnnotation, ParameterDescriptor, descriptorOf;
import flint.java.classref : ClassRef, classOf;
import flint.java.lang : IllegalArgumentException, IllegalStateException;
import std.exception : assertThrown, collectException;
import std.typecons : Nullable;

@safe:

private final class Document
{
    long revision;
}

private final class RevisionProperty : PersistentProperty!RevisionProperty
{
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
        return true;
    }

    override bool isAssociation()
    {
        return false;
    }
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
