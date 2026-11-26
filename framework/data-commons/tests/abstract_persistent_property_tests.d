// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/mapping/model/AbstractPersistentPropertyUnitTests.java
// Copyright 2011-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module abstract_persistent_property_tests;

import flint.data.core : TypeInformation;
import flint.data.mapping : PersistentEntity;
import flint.data.mapping.model : AbstractPersistentProperty, BasicPersistentEntity;
import flint.engine.aot.descriptor : DescriptorTable, descriptorOf;
import flint.java.classref : ClassRef, classOf;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : List, Map, Set;
import std.exception : collectException;

@safe:

private final class Person
{
    int id;
}

private final class Sample
{
    Person person;
    List!Person persons;
    Person[] personArray;
    Map!(string, Person) personMap;
}

private final class TestClassComplex
{
    Set!Object testClassSet;
    string var_name_with_underscores;
}

private final class SamplePersistentProperty : AbstractPersistentProperty!SamplePersistentProperty
{
    this(string name, PersistentEntity!() owner)
    {
        super(name, owner);
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
        return false;
    }

    override bool isAssociation()
    {
        return false;
    }
}

private PersistentEntity!() declaringEntity(T, Types...)()
{
    auto table = DescriptorTable.withBuiltins();
    table.add(descriptorOf!T());
    static foreach (Type; Types)
        table.add(descriptorOf!Type());
    return new BasicPersistentEntity!(T, SamplePersistentProperty)(TypeInformation.of!T(table));
}

@("resolvesActualType")
unittest
{
    auto owner = declaringEntity!(Sample, Person, List!Person, Person[], Map!(string, Person))();
    auto person = new SamplePersistentProperty("person", owner);
    assert(person.getActualType() == classOf!Person);
    assert(person.getComponentType() == ClassRef.init);

    auto persons = new SamplePersistentProperty("persons", owner);
    assert(persons.getActualType() == classOf!Person);
    assert(persons.getType() == classOf!(List!Person));

    auto array = new SamplePersistentProperty("personArray", owner);
    assert(array.getActualType() == classOf!Person);
    assert(array.getType() == classOf!(Person[]));

    auto map = new SamplePersistentProperty("personMap", owner);
    assert(map.getActualType() == classOf!Person);
    assert(map.getType() == classOf!(Map!(string, Person)));
    assert(map.getComponentType() == classOf!string);
}

@("discoversComponentTypeCorrectly")
unittest
{
    auto owner = declaringEntity!(TestClassComplex, Set!Object, Object)();
    auto property = new SamplePersistentProperty("testClassSet", owner);
    assert(property.getComponentType() == classOf!Object);
}

@("resolvesFieldNameWithUnderscoresCorrectly")
unittest
{
    auto owner = declaringEntity!TestClassComplex();
    auto property = new SamplePersistentProperty("var_name_with_underscores", owner);
    assert(property.getName() == "var_name_with_underscores");
}

@("owner and type metadata describe the same registered property")
unittest
{
    auto owner = declaringEntity!(Sample, Person, List!Person)();
    auto property = new SamplePersistentProperty("persons", owner);
    assert(property.getOwner() is owner && property.getOwner().getType() == classOf!Sample);
    assert(property.getName() == "persons");
    auto information = property.getTypeInformation();
    assert(information is property.getTypeInformation());
    assert(information.equals(cast(Object) owner.getTypeInformation().getRequiredProperty("persons")));
    assert(collectException!IllegalArgumentException(new SamplePersistentProperty("missing", owner)) !is null);
    assert(collectException!IllegalArgumentException(new SamplePersistentProperty("persons", null)) !is null);
}
