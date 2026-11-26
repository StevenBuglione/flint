// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/mapping/model/BasicPersistentEntityUnitTests.java
// Copyright 2011-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module basic_persistent_entity_tests;

import flint.core.annotation : AliasFor;
import flint.core.annotation.types : AnnotationConfigurationException;
import flint.data.annotation : CreatedBy, CreatedDate, Immutable, LastModifiedBy, Reference, Transient, TypeAlias;
import flint.data.core : TypeInformation;
import flint.data.domain : Persistable;
import flint.data.mapping : Alias, Association, AssociationHandler, MappingException,
    PersistentEntity, PersistentProperty, PropertyHandler;
import flint.data.mapping.model : BasicPersistentEntity;
import flint.data.repository.core.support : PersistentEntityInformation;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : DescriptorTable, descriptorOf;
import flint.java.classref : ClassRef, classOf;
import flint.java.lang : IllegalArgumentException, IllegalStateException, Long, NullPointerException;
import flint.java.util : Comparator;
import std.exception : assertThrown, collectException;
import std.typecons : Nullable;

@safe:

private class Person
{
    Nullable!long id;
    long revision;

    string getLabel() const
    {
        return "person";
    }
}

private final class Employee : Person
{
}

private struct Snapshot
{
    long revision;
    private long[5] padding;
}

private final class AuditedProperties
{
    @LastModifiedBy
    long field;

    @LastModifiedBy
    long secondField;

    @CreatedBy
    long getProperty() const
    {
        return field;
    }
}

private final class WithAssociation
{
    string property;

    @Reference
    WithAssociation association;
}

@TypeAlias("foo")
private class AliasedEntity
{
}

private final class DerivedAliasedEntity : AliasedEntity
{
}

@TypeAlias("foo")
private struct ComposedTypeAlias
{
    @AliasFor(annotation: classOf!TypeAlias, attribute: "value")
    string name = "bar";
}

@ComposedTypeAlias
private final class ComposedAliasedEntity : AliasedEntity
{
}

private struct InvalidAlias
{
    @AliasFor(attribute: "a", value: "b")
    string a;
}

@InvalidAlias
private final class EntityWithInvalidAlias
{
}

@TypeAlias("\u2003\t")
private final class WhitespaceAlias
{
}

@Immutable
private class ImmutableEntity
{
}

private final class DerivedImmutableEntity : ImmutableEntity
{
}

private final class AssignedId : Persistable!long
{
    override Nullable!long getId()
    {
        return Nullable!long(4711L);
    }

    override bool isNew()
    {
        return true;
    }
}

private final class Property : PersistentProperty!Property
{
    private string name;
    private ClassRef type;
    private bool identifier;
    private bool versioned;
    private bool transient_;
    private bool association;

    this(string name, ClassRef type = ClassRef.init, bool identifier = false, bool versioned = false,
            bool transient_ = false, bool association = false)
    {
        this.name = name;
        this.type = type;
        this.identifier = identifier;
        this.versioned = versioned;
        this.transient_ = transient_;
        this.association = association;
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
        return identifier;
    }

    override bool isVersionProperty()
    {
        return versioned;
    }

    override bool isTransient()
    {
        return transient_;
    }

    override bool isAssociation()
    {
        return association;
    }
}

private final class RecordingPropertyHandler : PropertyHandler!Property
{
    private Property[] seen;

    override void doWithPersistentProperty(Property property)
    {
        seen ~= property;
    }
}

private final class RecordingAssociationHandler : AssociationHandler!Property
{
    private Association!Property[] seen;

    override void doWithAssociation(Association!Property association)
    {
        seen ~= association;
    }
}

private BasicPersistentEntity!(T, Property) mapped(T)(Comparator!Property comparator = null)
{
    auto descriptors = DescriptorTable.withBuiltins();
    descriptors.add(descriptorOf!T());
    descriptors.add(descriptorOf!(Nullable!long)());
    return new BasicPersistentEntity!(T, Property)(TypeInformation.of!T(descriptors), comparator);
}

@("rejectsNullTypeInformation")
unittest
{
    assertThrown!IllegalArgumentException(new BasicPersistentEntity!(Person, Property)(null));
}

@("rejectsNullProperty")
unittest
{
    auto entity = mapped!Person();
    assertThrown!IllegalArgumentException(entity.addPersistentProperty(null));
}

@("returnsNullForTypeAliasIfNoneConfigured")
unittest
{
    auto entity = mapped!Person();
    assert(entity.getTypeAlias() is Alias.NONE);
    assert(entity.getType() == classOf!Person && entity.getName() == classOf!Person.name);
}

@("returnsTypeAliasIfAnnotated")
unittest
{
    assert(mapped!AliasedEntity().getTypeAlias() == Alias.of(Any.of("foo")));
}

@("returnsTypeAliasIfAnnotatedUsingComposedAnnotation")
unittest
{
    assert(mapped!ComposedAliasedEntity().getTypeAlias() == Alias.of(Any.of("bar")));
}

@("getRequiredAnnotationReturnsAnnotation")
unittest
{
    PersistentEntity!(ComposedAliasedEntity, Property) entity = mapped!ComposedAliasedEntity();
    assert(entity.getRequiredAnnotation(classOf!TypeAlias).get!(const TypeAlias).value == "bar");
    assert(entity.isAnnotationPresent(classOf!TypeAlias));
    assert(entity.findAnnotation(classOf!TypeAlias).get!(const TypeAlias).value == "bar");
}

@("getRequiredAnnotationThrowsException")
unittest
{
    import std.algorithm.searching : canFind;

    PersistentEntity!(ComposedAliasedEntity, Property) entity = mapped!ComposedAliasedEntity();
    auto missing = collectException!IllegalStateException(entity.getRequiredAnnotation(classOf!Transient));
    assert(missing !is null && missing.msg.canFind(classOf!Transient.name));
    assert(!entity.isAnnotationPresent(classOf!Transient));
    assert(entity.findAnnotation(classOf!Transient).isNull());
    assertThrown!NullPointerException(entity.findAnnotation(ClassRef.init));
}

@("throws for malformed aliases in registered annotation metadata")
unittest
{
    auto entity = mapped!EntityWithInvalidAlias();
    assertThrown!AnnotationConfigurationException(entity.findAnnotation(classOf!InvalidAlias));
    assertThrown!AnnotationConfigurationException(entity.isAnnotationPresent(classOf!InvalidAlias));
}

@("resolves a type alias on the domain type hierarchy")
unittest
{
    assert(mapped!DerivedAliasedEntity().getTypeAlias() == Alias.of(Any.of("foo")));
}

@("detectsImmutableEntity")
unittest
{
    PersistentEntity!(ImmutableEntity, Property) immutableEntity = mapped!ImmutableEntity();
    PersistentEntity!(Person, Property) ordinaryEntity = mapped!Person();
    assert(immutableEntity.isImmutable());
    assert(!ordinaryEntity.isImmutable());
}

@("immutable metadata follows the registered type hierarchy")
unittest
{
    assert(mapped!DerivedImmutableEntity().isImmutable());
}

@("requires text in a type alias annotation")
unittest
{
    assert(mapped!WhitespaceAlias().getTypeAlias() is Alias.NONE);
}

@("considersComparatorForPropertyOrder")
unittest
{
    auto comparator = Comparator!Property.comparing!string((Property property) => property.getName());
    auto entity = mapped!Person(comparator);
    entity.addPersistentProperty(new Property("lastName"));
    entity.addPersistentProperty(new Property("firstName"));
    entity.addPersistentProperty(new Property("ssn"));
    entity.verify();
    auto properties = entity.iterator();
    foreach (name; ["firstName", "lastName", "ssn"])
        assert(properties.next() is entity.getPersistentProperty(name));
    assert(!properties.hasNext());
}

@("addingAndIdPropertySetsIdPropertyInternally")
unittest
{
    auto entity = mapped!Person();
    assert(!entity.hasIdProperty());
    auto property = new Property("id", classOf!Long, true);
    entity.addPersistentProperty(property);
    entity.addPersistentProperty(property);
    assert(entity.getIdProperty() is property && entity.getRequiredIdProperty() is property);
    auto properties = entity.iterator();
    assert(properties.next() is property && !properties.hasNext());
}

@("sort preserves first-registration name lookup")
unittest
{
    auto comparator = Comparator!Property.comparing!bool((Property property) => property.isIdProperty());
    auto entity = mapped!Person(comparator);
    auto first = new Property("id", classOf!Long, true);
    auto second = new Property("id", classOf!Long);
    entity.addPersistentProperty(first);
    entity.addPersistentProperty(second);
    entity.verify();
    assert(entity.iterator().next() is second);
    assert(entity.getPersistentProperty("id") is first);
}

@("rejectsIdPropertyIfAlreadySet")
unittest
{
    auto entity = mapped!Person();
    auto property = new Property("id", classOf!Long, true);
    entity.addPersistentProperty(property);
    assertThrown!MappingException(entity.addPersistentProperty(new Property("other", classOf!Long, true)));
    assert(entity.getIdProperty() is property && entity.getPersistentProperty("other") is null);
}

@("descriptor reads preserve boxed identifiers and version precedence")
unittest
{
    auto entity = mapped!Person();
    entity.addPersistentProperty(new Property("id", classOf!Long, true));
    auto information = new PersistentEntityInformation!(Person, long)(entity);
    auto person = new Person;
    assert(information.getId(person).isNull && information.isNew(person));
    person.id = Nullable!long(0L);
    assert(information.getRequiredId(person) == 0L && !information.isNew(person));
    entity.addPersistentProperty(new Property("revision", classOf!long, false, true));
    assert(information.isNew(person));
    person.revision = 1;
    assert(!information.isNew(person));
    assertThrown!MappingException(entity.addPersistentProperty(new Property("other", classOf!long, false, true)));
    assert(entity.getVersionProperty().getName() == "revision" && entity.getPersistentProperty("other") is null);

    assertThrown!IllegalArgumentException(entity.getIdentifierAccessor(Any.of(new AssignedId)));
}

@("supportsPersistableViaIdentifierAccessor")
unittest
{
    auto entity = mapped!AssignedId();
    auto bean = Any.of(new AssignedId);
    assert(entity.getIdentifierAccessor(bean).getRequiredIdentifier().get!long == 4711);
    assert(entity.isNew(bean));
}

@("transient registration is separate from persistent lookup and iteration")
unittest
{
    auto entity = mapped!Person();
    auto identifier = new Property("id", classOf!Long, true);
    auto transientProperty = new Property("revision", classOf!long, false, true, true);
    entity.addPersistentProperty(identifier);
    entity.addPersistentProperty(transientProperty);
    entity.addPersistentProperty(transientProperty);
    assert(entity.getTransientProperty("revision") is transientProperty);
    assert(entity.isTransient("revision") && !entity.isTransient("id"));
    assert(!entity.hasVersionProperty() && entity.getPersistentProperty("revision") is null);
    auto properties = entity.iterator();
    assert(properties.next() is identifier && !properties.hasNext());
}

@("rejectsNullBeanForPropertyAccessor")
unittest
{
    PersistentEntity!(Person, Property) entity = mapped!Person();
    assertThrown!IllegalArgumentException(entity.getPropertyAccessor(Any.init));
}

@("reportsRequiredPropertyName")
unittest
{
    import std.algorithm.searching : canFind;

    auto model = mapped!Person();
    auto revision = new Property("revision", classOf!long);
    model.addPersistentProperty(revision);
    PersistentEntity!(Person, Property) entity = model;
    assert(entity.getRequiredPersistentProperty("revision") is revision);
    assert(entity.getPersistentProperty("foo") is null);
    auto missing = collectException!IllegalStateException(entity.getRequiredPersistentProperty("foo"));
    assert(missing !is null && missing.msg.canFind("Required property foo not found"));
    assert(missing.msg.canFind(classOf!Person.name));
    assert(entity.getPersistentProperty(null) is null);
    assertThrown!IllegalStateException(entity.getRequiredPersistentProperty(null));
}

@("detectsPropertyWithAnnotation")
unittest
{
    auto model = mapped!AuditedProperties();
    model.addPersistentProperty(new Property("field"));
    model.addPersistentProperty(new Property("property"));
    PersistentEntity!(AuditedProperties, Property) entity = model;
    assert(entity.getPersistentProperty(classOf!LastModifiedBy).getName() == "field");
    assert(entity.getPersistentProperty(classOf!CreatedBy).getName() == "property");
    assert(model.getPersistentProperty(classOf!CreatedBy) is entity.getPersistentProperty("property"));
    assert(entity.getPersistentProperty(classOf!CreatedDate) is null);
}

@("annotation lookup returns a snapshot in current property order")
unittest
{
    auto comparator = Comparator!Property.comparing!string((Property property) => property.getName());
    auto model = mapped!AuditedProperties(comparator);
    auto second = new Property("secondField");
    model.addPersistentProperty(second);
    PersistentEntity!(AuditedProperties, Property) entity = model;
    auto prior = entity.getPersistentProperties(classOf!LastModifiedBy);
    auto first = new Property("field");
    model.addPersistentProperty(first);
    model.verify();

    auto before = prior.iterator();
    assert(before.next() is second && !before.hasNext());
    auto current = entity.getPersistentProperties(classOf!LastModifiedBy).iterator();
    assert(current.next() is first && current.next() is second && !current.hasNext());
    assert(entity.getPersistentProperty("field") is first);
    assert(!entity.getPersistentProperties(classOf!CreatedDate).iterator().hasNext());
    assertThrown!IllegalArgumentException(entity.getPersistentProperties(ClassRef.init));
}

@("rejectsNullAssociation")
unittest
{
    auto model = mapped!AuditedProperties();
    assertThrown!IllegalArgumentException(model.addAssociation(null));
}

@("annotation lookup falls back to ordered inverse association properties")
unittest
{
    auto comparator = Comparator!Property.comparing!string((Property property) => property.getName());
    auto model = mapped!AuditedProperties(comparator);
    auto first = new Property("field");
    auto second = new Property("secondField");
    auto obverse = new Property("property");
    auto association = new Association!Property(second, obverse);
    assert(association.getInverse() is second && association.getObverse() is obverse);
    auto inverseOnly = new Association!Property(first, null);
    assert(inverseOnly.getObverse() is null);

    model.addAssociation(association);
    model.addAssociation(inverseOnly);
    model.addAssociation(new Association!Property(new Property("field"), obverse));
    PersistentEntity!(AuditedProperties, Property) entity = model;
    auto matches = entity.getPersistentProperties(classOf!LastModifiedBy).iterator();
    assert(matches.next() is first && matches.next() is second && !matches.hasNext());
    assert(entity.getPersistentProperty(classOf!CreatedBy) is null);

    model.addPersistentProperty(second);
    matches = entity.getPersistentProperties(classOf!LastModifiedBy).iterator();
    assert(matches.next() is second && !matches.hasNext());
}

@("association registration without a comparator keeps distinct objects")
unittest
{
    auto model = mapped!AuditedProperties();
    auto first = new Property("secondField");
    auto second = new Property("field");
    auto association = new Association!Property(first, null);
    model.addAssociation(association);
    model.addAssociation(association);
    model.addAssociation(new Association!Property(second, null));
    model.addAssociation(new Association!Property(first, null));

    auto matches = model.getPersistentProperties(classOf!LastModifiedBy).iterator();
    foreach (expected; [first, second, first])
        assert(matches.next() is expected);
    assert(!matches.hasNext());
}

@("required version property follows registration")
unittest
{
    auto model = mapped!Person();
    PersistentEntity!(Person, Property) entity = model;
    assert(!entity.hasVersionProperty() && entity.getVersionProperty() is null);
    assertThrown!IllegalStateException(entity.getRequiredVersionProperty());

    auto revision = new Property("revision", classOf!long, false, true);
    model.addPersistentProperty(revision);
    assert(entity.hasVersionProperty());
    assert(entity.getRequiredVersionProperty() is revision);
}

@("association handlers and delegates receive registered associations in order")
unittest
{
    Comparator!Property[] comparators = [
        null, Comparator!Property.comparing!string((Property property) => property.getName())
    ];
    foreach (comparator; comparators)
    {
        auto model = mapped!AuditedProperties(comparator);
        auto first = new Association!Property(new Property("secondField"), null);
        auto second = new Association!Property(new Property("field"), null);
        model.addAssociation(first);
        model.addAssociation(second);
        const expected = comparator is null ? [first, second] : [second, first];

        PersistentEntity!(AuditedProperties, Property) entity = model;
        auto visitor = new RecordingAssociationHandler;
        entity.doWithAssociations(visitor);
        assert(visitor.seen == expected);
        Association!Property[] visited;
        entity.doWithAssociations((association) { visited ~= association; });
        assert(visited == expected);
    }
}

@("association traversal validates handlers on an empty entity")
unittest
{
    auto entity = mapped!AuditedProperties();
    auto visitor = new RecordingAssociationHandler;
    entity.doWithAssociations(visitor);
    assert(visitor.seen.length == 0);
    assertThrown!IllegalArgumentException(entity.doWithAssociations(cast(AssociationHandler!Property) null));
    alias AssociationAction = void delegate(Association!Property) @safe;
    assertThrown!IllegalArgumentException(entity.doWithAssociations(cast(AssociationAction) null));
}

@("doWithAllInvokesPropertyHandlerForBothAPropertiesAndAssociations")
unittest
{
    auto model = mapped!WithAssociation();
    auto inverse = new Property("association", classOf!WithAssociation, association:
            true);
    auto ordinary = new Property("property", classOf!string);
    model.addPersistentProperty(inverse);
    model.addPersistentProperty(ordinary);
    model.addAssociation(new Association!Property(inverse, null));
    PersistentEntity!(WithAssociation, Property) entity = model;

    auto visitor = new RecordingPropertyHandler;
    entity.doWithProperties(visitor);
    assert(visitor.seen == [ordinary]);
    auto combinedVisitor = new RecordingPropertyHandler;
    entity.doWithAll(combinedVisitor);
    assert(combinedVisitor.seen == [ordinary, inverse]);

    Property[] seen;
    entity.doWithAll((property) { seen ~= property; });
    assert(seen == [ordinary, inverse]);
    auto properties = entity.iterator();
    assert(properties.next() is inverse && properties.next() is ordinary && !properties.hasNext());
}

@("property traversal rejects null handlers before visiting anything")
unittest
{
    auto entity = mapped!WithAssociation();
    assertThrown!IllegalArgumentException(entity.doWithProperties(cast(PropertyHandler!Property) null));
    assertThrown!IllegalArgumentException(entity.doWithAll(cast(PropertyHandler!Property) null));
    alias PropertyAction = void delegate(Property) @safe;
    assertThrown!IllegalArgumentException(entity.doWithProperties(cast(PropertyAction) null));
    assertThrown!IllegalArgumentException(entity.doWithAll(cast(PropertyAction) null));
}

@("rejectsNonMatchingBeanForPropertyAccessor")
unittest
{
    PersistentEntity!(Person, Property) entity = mapped!Person();
    assertThrown!IllegalArgumentException(entity.getPropertyAccessor(Any.of("foo")));
}

@("supportsSubtypeInstancesOnPropertyAccessorLookup")
unittest
{
    PersistentEntity!(Person, Property) entity = mapped!Person();
    auto bean = new Employee;
    auto accessor = entity.getPropertyAccessor(Any.of(bean));
    assert(accessor.getBean() is bean);

    auto revision = new Property("revision", classOf!long);
    entity.getPropertyAccessor(Any.of(bean)).setProperty(revision, Any.of(3L));
    assert(accessor.getProperty(revision).get!long == 3L && bean.revision == 3L);
}

@("invalidBeanAccessCreatesDescriptiveErrorMessage")
unittest
{
    import std.algorithm.searching : canFind;

    auto failure = collectException!IllegalArgumentException(mapped!Person().getPropertyAccessor(Any.of(new Object)));
    assert(failure !is null);
    assert(failure.msg.canFind(classOf!Person.name) && failure.msg.canFind(classOf!Object.name));
}

@("descriptor access reports unavailable or invalid writes")
unittest
{
    auto accessor = mapped!Person().getPropertyAccessor(Any.of(new Person));
    auto revision = new Property("revision", classOf!long);
    auto failure = collectException!MappingException(accessor.setProperty(revision, Any.of("bad")));
    assert(failure !is null && failure.getCause() !is null);
    assert(accessor.getProperty(revision).get!long == 0);
    auto label = new Property("label", classOf!string);
    assert(accessor.getProperty(label).get!string == "person");
    assertThrown!MappingException(accessor.setProperty(label, Any.of("updated")));
    assertThrown!MappingException(accessor.getProperty(new Property("missing")));
    assertThrown!IllegalArgumentException(accessor.getProperty(null));
}

@("descriptor access owns a copy of a boxed struct bean")
unittest
{
    auto original = Any.of(Snapshot(1L));
    auto accessor = mapped!Snapshot().getPropertyAccessor(original);
    auto revision = new Property("revision", classOf!long);
    accessor.setProperty(revision, Any.of(2L));
    assert(accessor.getBean().revision == 2L && original.get!Snapshot.revision == 1L);
}
