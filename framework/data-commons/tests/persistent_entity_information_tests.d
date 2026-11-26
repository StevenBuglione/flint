// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/repository/core/support/PersistentEntityInformationUnitTests.java
// Copyright 2014-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module persistent_entity_information_tests;

import flint.data.annotation : Id;
import flint.data.core : TypeInformation;
import flint.data.mapping : PersistentEntity, PersistentProperty;
import flint.data.mapping.model : BasicPersistentEntity;
import flint.data.repository.core : EntityInformation;
import flint.data.repository.core.support : PersistentEntityInformation;
import flint.engine.aot.descriptor : DescriptorTable, PropertyDescriptor, descriptorOf;
import flint.java.classref : ClassRef, classOf;
import flint.java.lang : IllegalStateException, Long;
import std.exception : assertThrown;
import std.typecons : Nullable;

@safe:

private final class Sample
{
    @Id
    Nullable!long id;
}

private final class EntityWithoutId
{
    long value;
}

private final class MappedProperty : PersistentProperty!MappedProperty
{
    const(PropertyDescriptor)* property;
    ClassRef declaredType;

    this(const(PropertyDescriptor)* property, ClassRef declaredType)
    {
        this.property = property;
        this.declaredType = declaredType;
    }

    override string getName()
    {
        return property.name;
    }

    override ClassRef getType()
    {
        return declaredType;
    }

    override bool isIdProperty()
    {
        foreach (ref annotation; property.annotations)
            if (annotation.type == classOf!Id.name)
                return true;
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
}

private BasicPersistentEntity!(T, MappedProperty) mappedEntity(T)(const(DescriptorTable) descriptors,
        ClassRef boxedIdType = ClassRef.init)
{
    const descriptor = descriptors.find(classOf!T.name);
    auto entity = new BasicPersistentEntity!(T, MappedProperty)(TypeInformation.of!T(descriptors));
    foreach (ref property; descriptor.properties)
    {
        auto mapped = new MappedProperty(&property, ClassRef(property.type));
        if (boxedIdType.name.length && mapped.isIdProperty())
            mapped.declaredType = boxedIdType;
        entity.addPersistentProperty(mapped);
    }
    return entity;
}

static assert(!__traits(compiles, PersistentEntity!(Sample, string)));

@("obtainsIdAndIdTypeInformationFromPersistentEntity")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    descriptors.add(descriptorOf!Sample());
    descriptors.add(descriptorOf!(Nullable!long)());

    auto mapped = mappedEntity!Sample(descriptors, classOf!Long);
    PersistentEntity!(Sample, MappedProperty) entity = mapped;
    EntityInformation!(Sample, long) information = new PersistentEntityInformation!(Sample, long)(mapped);
    assert(entity.hasIdProperty() && entity.getRequiredIdProperty().getName() == "id");
    assert(entity.iterator().next() is entity.getIdProperty());
    assert(entity.getName() == classOf!Sample.name && information.getJavaType() == classOf!Sample);
    assert(entity.getTypeInformation().getRequiredProperty("id").getRequiredActualType().getType() == classOf!long);
    assert(information.getIdType() == classOf!Long);

    auto sample = new Sample;
    assert(information.isNew(sample) && information.getId(sample).isNull);
    sample.id = Nullable!long(0L);
    assert(!information.isNew(sample) && information.getRequiredId(sample) == 0L);
    sample.id = Nullable!long(5L);
    assert(information.getId(sample).get == 5L);
}

@("returnsNullIfNoIdPropertyPresent")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    descriptors.add(descriptorOf!EntityWithoutId());

    PersistentEntity!(EntityWithoutId, MappedProperty) entity = mappedEntity!EntityWithoutId(descriptors);
    EntityInformation!(EntityWithoutId, Object) information = new PersistentEntityInformation!(EntityWithoutId, Object)(
            entity);
    assert(!entity.hasIdProperty() && entity.getIdProperty() is null);
    assert(information.getId(new EntityWithoutId) is null);
    assertThrown!IllegalStateException(information.getIdType());
}

private final class EntityWithReferenceId
{
    @Id
    Object id;
}

@("the repository adapter preserves identifier reference identity")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    descriptors.add(descriptorOf!EntityWithReferenceId());
    auto entity = mappedEntity!EntityWithReferenceId(descriptors);
    auto information = new PersistentEntityInformation!(EntityWithReferenceId, Object)(entity);
    auto sample = new EntityWithReferenceId;
    assert(information.getId(sample) is null);
    auto identifier = new Object;
    sample.id = identifier;
    assert(information.getId(sample) is identifier);
    assert(information.getRequiredId(sample) is identifier);
}
