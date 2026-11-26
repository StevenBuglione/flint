// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/repository/core/support/PersistentEntityInformationUnitTests.java
// Copyright 2014-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module persistent_entity_information_tests;

import flint.data.annotation : Id;
import flint.data.core : TypeInformation;
import flint.data.mapping : Alias, IdentifierAccessor, PersistentEntity, PersistentProperty,
    TargetAwareIdentifierAccessor;
import flint.data.repository.core : EntityInformation;
import flint.data.repository.core.support : PersistentEntityInformation;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, DescriptorTable, PropertyDescriptor, descriptorOf;
import flint.java.classref : ClassRef, classOf;
import flint.java.lang : IllegalStateException, Long;
import flint.java.util : ArrayList, Iterator, List;
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
    const(Descriptor) wrapper;
    ClassRef declaredType;

    this(const(PropertyDescriptor)* property, const(Descriptor) wrapper, ClassRef declaredType)
    {
        this.property = property;
        this.wrapper = wrapper;
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

    Any read(ref Any bean)
    {
        auto value = property.get(bean);
        return wrapper !is null && wrapper.unwrap !is null ? wrapper.unwrap(value) : value;
    }
}

private final class MappedIdentifierAccessor : TargetAwareIdentifierAccessor
{
    private Any bean;
    private MappedProperty property;

    this(Any bean, MappedProperty property)
    {
        super(bean);
        this.bean = bean;
        this.property = property;
    }

    override Any getIdentifier()
    {
        return property is null ? Any.init : property.read(bean);
    }
}

private final class MappedEntity(T) : PersistentEntity!(T, MappedProperty)
{
    private MappedProperty identifier;
    private List!MappedProperty properties;
    private TypeInformation typeInformation;

    this(const(DescriptorTable) descriptors, ClassRef boxedIdType = ClassRef.init)
    {
        const descriptor = descriptors.find(classOf!T.name);
        typeInformation = TypeInformation.of!T(descriptors);
        properties = new ArrayList!MappedProperty(cast(int) descriptor.properties.length);
        foreach (i; 0 .. descriptor.properties.length)
        {
            const property = &descriptor.properties[i];
            bool denotesId;
            foreach (ref annotation; property.annotations)
                if (annotation.type == classOf!Id.name)
                {
                    denotesId = true;
                    break;
                }

            const declaredType = denotesId && boxedIdType.name.length ? boxedIdType : ClassRef(property.type);
            auto mapped = new MappedProperty(property, descriptors.find(property.type), declaredType);
            properties.add(mapped);
            if (denotesId)
                identifier = mapped;
        }
    }

    mixin PersistentEntity!(T, MappedProperty).Defaults;

    override string getName()
    {
        return classOf!T.name;
    }

    override ClassRef getType()
    {
        return classOf!T;
    }

    override TypeInformation getTypeInformation()
    {
        return typeInformation;
    }

    override Alias getTypeAlias()
    {
        return Alias.NONE;
    }

    override MappedProperty getIdProperty()
    {
        return identifier;
    }

    override bool hasIdProperty()
    {
        return identifier !is null;
    }

    override IdentifierAccessor getIdentifierAccessor(Any bean)
    {
        return new MappedIdentifierAccessor(bean, identifier);
    }

    override bool isNew(Any bean)
    {
        return identifier is null || identifier.read(bean).isNull();
    }

    override Iterator!MappedProperty iterator()
    {
        return properties.iterator();
    }

    override void forEach(void delegate(MappedProperty) @safe action)
    {
        properties.forEach(action);
    }

    override int opApply(scope int delegate(MappedProperty) @safe action)
    {
        return properties.opApply(action);
    }
}

static assert(!__traits(compiles, PersistentEntity!(Sample, string)));

@("obtainsIdAndIdTypeInformationFromPersistentEntity")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    descriptors.add(descriptorOf!Sample());
    descriptors.add(descriptorOf!(Nullable!long)());

    auto mapped = new MappedEntity!Sample(descriptors, classOf!Long);
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

    PersistentEntity!(EntityWithoutId, MappedProperty) entity = new MappedEntity!EntityWithoutId(descriptors);
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
    auto entity = new MappedEntity!EntityWithReferenceId(descriptors);
    auto information = new PersistentEntityInformation!(EntityWithReferenceId, Object)(entity);
    auto sample = new EntityWithReferenceId;
    assert(information.getId(sample) is null);
    auto identifier = new Object;
    sample.id = identifier;
    assert(information.getId(sample) is identifier);
    assert(information.getRequiredId(sample) is identifier);
}
