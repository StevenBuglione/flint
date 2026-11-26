// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/mapping/model/{BasicPersistentEntity,BeanWrapper,BeanWrapperPropertyAccessorFactory,MutablePersistentEntity,PersistentPropertyAccessorFactory,PreferredConstructorDiscoverer}.java
// Copyright 2011-present the original author or authors.
// Accessor factories: Copyright 2016-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.mapping.model;

import flint.context : EnvironmentAware;
import flint.core.annotation.types : AnnotationConfigurationException;
import flint.core.env : Environment, EnvironmentCapable, StandardEnvironment;
import flint.data.annotation : Immutable, PersistenceCreator, TypeAlias;
import flint.data.core.type_information : TypeInformation, registeredDescriptor, registeredTypeInformation;
import flint.data.domain.persistable : PersistableState;
import flint.data.mapping : Alias, Association, AssociationHandler, IdentifierAccessor,
    InstanceCreatorMetadata, MappingException, Parameter, PersistentEntity,
    PersistentProperty, PersistentPropertyAccessor,
    PreferredConstructor, PrimitivePropertyKind, PropertyHandler, TargetAwareIdentifierAccessor,
    primitivePropertyKind;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : ConstructorDescriptor, Descriptor, DescriptorTable,
    MergedAnnotation, PropertyDescriptor, findMergedAnnotation = findAnnotation;
import flint.engine.aot.objects : statelessInstance;
import flint.java.classref : ClassRef, classOf;
import flint.java.lang : IllegalArgumentException, Iterable, NullPointerException;
import flint.java.util : ArrayList, Collections, Comparator, HashMap, Iterator, List, Map, Objects;
import flint.util : StringUtils;
import std.typecons : Nullable;

@safe:

/// Entity metadata that accepts registrations during startup.
interface MutablePersistentEntity(T, P) : PersistentEntity!(T, P), EnvironmentAware
        if (is(P : PersistentProperty!P))
{
    /// Registers a property with the entity.
    void addPersistentProperty(P property);

    /// Registers an association with the entity.
    void addAssociation(Association!P association);

    /// Verifies and prepares the registered entity metadata.
    void verify();

    /// Supplies a non-null factory for property accessors.
    void setPersistentPropertyAccessorFactory(PersistentPropertyAccessorFactory!(T, P) factory);
}

/// Creates property accessors for the given entity and property types.
interface PersistentPropertyAccessorFactory(T, P) if (is(P : PersistentProperty!P))
{
    /// Creates an accessor for the supplied entity and bean.
    PersistentPropertyAccessor!(T, P) getPropertyAccessor(PersistentEntity!(T, P) entity, Any bean);

    /// Whether the factory can create accessors for this entity metadata.
    bool isSupported(PersistentEntity!(T, P) entity);
}

/// The standard property accessor factory for registered descriptors.
final class BeanWrapperPropertyAccessorFactory(T, P) : PersistentPropertyAccessorFactory!(T,
        P) if (is(P : PersistentProperty!P))
{
    package(flint) this() pure nothrow @nogc
    {
    }

    /// The shared factory for this entity and property pair (R18).
    static BeanWrapperPropertyAccessorFactory INSTANCE() nothrow @nogc
    {
        return statelessInstance!BeanWrapperPropertyAccessorFactory();
    }

    /// The name of the enum constant.
    string name() pure nothrow @nogc
    {
        return "INSTANCE";
    }

    /// The zero-based ordinal of the enum constant.
    int ordinal() pure nothrow @nogc
    {
        return 0;
    }

    override string toString() pure nothrow @nogc
    {
        return name();
    }

    /// The constants, in declaration order.
    static BeanWrapperPropertyAccessorFactory[] values()
    {
        return [INSTANCE];
    }

    /// The constant by its exact name.
    static BeanWrapperPropertyAccessorFactory valueOf(string constant)
    {
        if (constant is null)
            throw new NullPointerException("Name is null");
        if (constant != "INSTANCE")
        {
            enum prefix = "No enum constant org.springframework.data.mapping.model.BeanWrapperPropertyAccessorFactory.";
            throw new IllegalArgumentException(prefix ~ constant);
        }
        return INSTANCE;
    }

    override PersistentPropertyAccessor!(T, P) getPropertyAccessor(PersistentEntity!(T, P) entity, Any bean)
    {
        if (entity is null)
            throw new IllegalArgumentException("Entity must not be null");
        verifyEntityBean!(T, P)(entity, bean);
        const descriptor = registeredDescriptor(entity.getTypeInformation());
        if (descriptor is null)
            throw new MappingException(Nullable!string("No registered descriptor for " ~ entity.getName()));
        return new BeanWrapper!(T, P)(descriptor, copyAccessorBean!T(bean));
    }

    override bool isSupported(PersistentEntity!(T, P) entity)
    {
        return entity !is null && registeredDescriptor(entity.getTypeInformation()) !is null;
    }

}

/// Mutable persistent metadata built from explicit property registration before serving requests.
class BasicPersistentEntity(T, P) : MutablePersistentEntity!(T, P), EnvironmentCapable
        if (is(P
            : PersistentProperty!P))
{
    private TypeInformation information;
    private const(Descriptor) descriptor;
    private Environment environment;
    private InstanceCreatorMetadata!(T, P) creator;
    private bool creatorResolved;
    private PersistentPropertyAccessorFactory!(T, P) propertyAccessorFactory;
    private Comparator!P comparator;
    private List!P properties;
    private List!P propertyView;
    private List!(Association!P) associations;
    private Map!(string, P) propertiesByName;
    private P[] transientProperties;
    private Alias typeAlias;
    private P idProperty;
    private P versionProperty;
    private PropertyRead idRead;
    private PropertyRead versionRead;

    /// Creates entity metadata with the given registered type information.
    this(TypeInformation information)
    {
        this(information, null);
    }

    /// Creates entity metadata with an optional persistent-property ordering.
    this(TypeInformation information, Comparator!P comparator)
    {
        if (information is null)
            throw new IllegalArgumentException("Information must not be null");
        this.information = information;
        this.comparator = comparator;
        properties = new ArrayList!P();
        propertyView = Collections.unmodifiableList(properties);
        propertiesByName = new HashMap!(string, P)();
        descriptor = registeredDescriptor(information);
        typeAlias = getAliasFromAnnotation(descriptor);
    }

    mixin PersistentEntity!(T, P).Defaults entityDefaults;
    alias getPersistentProperty = entityDefaults.getPersistentProperty;

    override string getName()
    {
        return getType().name;
    }

    override InstanceCreatorMetadata!(T, P) getInstanceCreatorMetadata()
    {
        synchronized (this)
        {
            if (!creatorResolved)
            {
                creator = PreferredConstructorDiscoverer.discover!(T, P)(this);
                creatorResolved = true;
            }
            return creator;
        }
    }

    override bool isCreatorArgument(PersistentProperty!() property)
    {
        if (property is null)
            return false;
        auto metadata = getInstanceCreatorMetadata();
        return metadata !is null && metadata.isCreatorParameter(property);
    }

    override ClassRef getType()
    {
        return information.getType();
    }

    override TypeInformation getTypeInformation()
    {
        return information;
    }

    /// The registered type alias, or Alias.NONE when absent.
    override Alias getTypeAlias()
    {
        return typeAlias;
    }

    override const(Any) findAnnotation(ClassRef annotationType)
    {
        return readEntityAnnotation(descriptor, annotationType);
    }

    override bool isAnnotationPresent(ClassRef annotationType)
    {
        return !readEntityAnnotation(descriptor, annotationType).isNull();
    }

    override bool isImmutable()
    {
        return isAnnotationPresent(classOf!Immutable);
    }

    override bool requiresPropertyPopulation()
    {
        if (isImmutable())
            return false;
        foreach (property; properties)
            if (!property.isTransient() && !isCreatorArgument(property))
                return true;
        return false;
    }

    override P getIdProperty()
    {
        return idProperty;
    }

    override bool hasIdProperty()
    {
        return idProperty !is null;
    }

    override bool isIdProperty(PersistentProperty!() property)
    {
        return idProperty !is null && Objects.equals(idProperty, property);
    }

    /// The version property, or null when no version is mapped.
    override P getVersionProperty()
    {
        return versionProperty;
    }

    /// Whether a version property is mapped.
    override bool hasVersionProperty()
    {
        return versionProperty !is null;
    }

    override bool isVersionProperty(PersistentProperty!() property)
    {
        return versionProperty !is null && Objects.equals(versionProperty, property);
    }

    /// Registers a property and remembers the identifier and version roles.
    override void addPersistentProperty(P property)
    {
        if (property is null)
            throw new IllegalArgumentException("Property must not be null");
        if (property.isTransient())
        {
            foreach (registered; transientProperties)
                if (Objects.equals(registered, property))
                    return;
            transientProperties ~= property;
            return;
        }
        if (properties.contains(property))
            return;

        const identifier = property.isIdProperty();
        const versioned = property.isVersionProperty();
        if (identifier && idProperty !is null)
            rejectDuplicate("id", property, idProperty);
        if (versioned && versionProperty !is null)
            rejectDuplicate("version", property, versionProperty);

        const name = property.getName();
        const reader = identifier || versioned ? bindRead(name) : PropertyRead.init;
        properties.add(property);
        propertiesByName.putIfAbsent(name, property);
        if (identifier)
        {
            idProperty = property;
            idRead = reader;
        }
        if (versioned)
        {
            versionProperty = property;
            versionRead = reader;
        }
    }

    /// The first persistent property registered under the name.
    override P getPersistentProperty(string name)
    {
        return propertiesByName.get(name);
    }

    /// Registers an association, respecting the inverse-property comparator when configured.
    override void addAssociation(Association!P association)
    {
        if (association is null)
            throw new IllegalArgumentException("Association must not be null");
        if (associations is null)
            associations = new ArrayList!(Association!P)();
        if (comparator is null)
        {
            if (!associations.contains(association))
                associations.add(association);
            return;
        }

        int index;
        foreach (registered; associations)
        {
            const order = comparator.compare(association.getInverse(), registered.getInverse());
            if (order == 0)
                return;
            if (order < 0)
                break;
            ++index;
        }
        associations.add(index, association);
    }

    override void doWithAssociations(AssociationHandler!P handler)
    {
        if (handler is null)
            throw new IllegalArgumentException("Handler must not be null");
        doWithAssociations(&handler.doWithAssociation);
    }

    override void doWithAssociations(scope void delegate(Association!P) @safe handler)
    {
        if (handler is null)
            throw new IllegalArgumentException("Handler must not be null");
        if (associations !is null)
            foreach (association; associations)
                handler(association);
    }

    override void doWithProperties(PropertyHandler!P handler)
    {
        if (handler is null)
            throw new IllegalArgumentException("PropertyHandler must not be null");
        doWithProperties(&handler.doWithPersistentProperty);
    }

    override void doWithProperties(scope void delegate(P) @safe handler)
    {
        if (handler is null)
            throw new IllegalArgumentException("PropertyHandler must not be null");
        foreach (property; properties)
            if (!property.isAssociation())
                handler(property);
    }

    override Iterable!P getPersistentProperties(ClassRef annotationType)
    {
        if (annotationType.name.length == 0)
            throw new IllegalArgumentException("Annotation type must not be null");
        if (descriptor is null)
            return Collections.emptyList!P();

        List!P matches;
        foreach (property; properties)
            addAnnotatedProperty(matches, property, annotationType.name);
        if (matches is null && associations !is null)
            foreach (association; associations)
                addAnnotatedProperty(matches, association.getInverse(), annotationType.name);
        return matches is null ? Collections.emptyList!P() : Collections.unmodifiableList(matches);
    }

    private void addAnnotatedProperty(ref List!P matches, P property, string annotationType)
    {
        if (property is null)
            return;
        const field = descriptor.property(property.getName());
        if (field is null || findCheckedAnnotation(field.annotations, annotationType) is null)
            return;
        if (matches is null)
            matches = new ArrayList!P();
        matches.add(property);
    }

    /// The last transient property registered under the name.
    override P getTransientProperty(string name)
    {
        foreach_reverse (property; transientProperties)
            if (property.getName() == name)
                return property;
        return null;
    }

    /// Whether the name belongs to a registered transient property.
    override bool isTransient(string name)
    {
        auto property = getTransientProperty(name);
        return property !is null && property.isTransient();
    }

    /// Applies the configured order after registration.
    override void verify()
    {
        if (comparator !is null)
            properties.sort(comparator);
    }

    /// Supplies the environment used by this entity metadata.
    override void setEnvironment(Environment environment)
    {
        this.environment = environment;
    }

    /// Returns the configured environment or lazily creates the standard one.
    override Environment getEnvironment()
    {
        if (environment is null)
            environment = new StandardEnvironment();
        return environment;
    }

    override IdentifierAccessor getIdentifierAccessor(Any bean)
    {
        verifyEntityBean!(T, P)(this, bean);
        static if (is(T : PersistableState))
            return new ModelIdentifierAccessor(bean, PropertyRead(&readPersistableId!T));
        else
            return new ModelIdentifierAccessor(bean, idRead);
    }

    override PersistentPropertyAccessor!(T, P) getPropertyAccessor(Any bean)
    {
        auto factory = propertyAccessorFactory;
        if (factory is null)
            return BeanWrapperPropertyAccessorFactory!(T, P).INSTANCE.getPropertyAccessor(this, bean);
        verifyEntityBean!(T, P)(this, bean);
        return factory.getPropertyAccessor(this, copyAccessorBean!T(bean));
    }

    override void setPersistentPropertyAccessorFactory(PersistentPropertyAccessorFactory!(T, P) factory)
    {
        if (factory is null)
            throw new IllegalArgumentException("PropertyAccessorFactory must not be null");
        propertyAccessorFactory = factory is BeanWrapperPropertyAccessorFactory!(T, P).INSTANCE ? null : factory;
    }

    override bool isNew(Any bean)
    {
        verifyEntityBean!(T, P)(this, bean);
        static if (is(T : PersistableState))
            return bean.get!T.isNew();
        else
        {
            if (versionProperty !is null)
                return isNewValue(versionRead, versionProperty.getType(), bean);
            return idProperty is null || isNewValue(idRead, idProperty.getType(), bean);
        }
    }

    override Iterator!P iterator()
    {
        return propertyView.iterator();
    }

    override void forEach(void delegate(P) @safe action)
    {
        propertyView.forEach(action);
    }

    override int opApply(scope int delegate(P) @safe action)
    {
        return propertyView.opApply(action);
    }

    private PropertyRead bindRead(string name)
    {
        auto field = descriptor is null ? null : descriptor.property(name);
        if (field is null || field.get is null)
            return PropertyRead(null, null, name);
        auto type = registeredDescriptor(information, field.type);
        return PropertyRead(field.get, type is null ? null : type.unwrap, name);
    }

    private static void rejectDuplicate(string role, P candidate, P existing)
    {
        const conflict = "Attempt to add " ~ role ~ " property " ~ candidate.getName();
        const registered = " but already have property " ~ existing.getName() ~ " registered as " ~ role;
        throw new MappingException(Nullable!string(conflict ~ registered ~ "; Check your mapping configuration"));
    }
}

private const(ConstructorDescriptor)* preferredConstructor(return scope const(ConstructorDescriptor)[] constructors)
{
    const(ConstructorDescriptor)* canonical;
    const(ConstructorDescriptor)* noArguments;
    foreach (ref candidate; constructors)
    {
        if (findCheckedAnnotation(candidate.annotations, classOf!PersistenceCreator.name) !is null)
            return &candidate;
        if (candidate.canonical && canonical is null)
            canonical = &candidate;
        if (!candidate.parameters.length && noArguments is null)
            noArguments = &candidate;
    }
    if (canonical !is null)
        return canonical;
    if (noArguments !is null)
        return noArguments;
    return constructors.length == 1 ? &constructors[0] : null;
}

/// Discovers the preferred constructor from registered Flint AOT metadata.
interface PreferredConstructorDiscoverer
{
    /// Finds the preferred constructor for the given type and descriptor table (R4, D-DATA-23).
    static PreferredConstructor!(T, P) discover(T, P)(const(DescriptorTable) descriptors)
            if (is(P : PersistentProperty!P))
    {
        return discoverType!(T, P)(TypeInformation.of!T(descriptors), null);
    }

    /// Finds the preferred constructor using the entity's registered type metadata.
    static PreferredConstructor!(T, P) discover(T, P)(PersistentEntity!(T, P) entity)
            if (is(P : PersistentProperty!P))
    {
        if (entity is null)
            throw new IllegalArgumentException("PersistentEntity must not be null");
        return discoverType!(T, P)(entity.getTypeInformation(), entity);
    }

    private static PreferredConstructor!(T, P) discoverType(T, P)(TypeInformation owner, PersistentEntity!(T, P) entity)
    {
        auto descriptor = registeredDescriptor(owner);
        if (descriptor is null)
            return null;
        auto selected = preferredConstructor(descriptor.constructors);
        if (selected is null)
            return null;
        if (!selected.parameters.length)
            return new PreferredConstructor!(T, P)(*selected);

        auto items = new ArrayList!(Parameter!(T, P))(cast(int) selected.parameters.length);
        foreach (ref declared; selected.parameters)
        {
            const name = declared.name is null ? Nullable!string.init : Nullable!string(declared.name);
            auto type = registeredTypeInformation(owner, declared.type);
            items.add(new Parameter!(T, P)(name, type, declared.annotations, entity));
        }
        return new PreferredConstructor!(T, P)(*selected, Collections.unmodifiableList(items));
    }
}

private Alias getAliasFromAnnotation(const Descriptor descriptor)
{
    if (descriptor is null)
        return Alias.NONE;
    const annotation = findMergedAnnotation(descriptor.annotations, classOf!TypeAlias.name);
    if (annotation is null)
        return Alias.NONE;
    const aliasValue = annotation.value.get!TypeAlias.value;
    return StringUtils.hasText(aliasValue) ? Alias.of(Any.of(aliasValue)) : Alias.NONE;
}

private const(Any) readEntityAnnotation(const Descriptor descriptor, ClassRef annotationType)
{
    if (annotationType.name.length == 0)
        throw new NullPointerException("Annotation type must not be null");
    if (descriptor is null)
        return const(Any).init;
    const match = findCheckedAnnotation(descriptor.annotations, annotationType.name);
    return match is null ? const(Any).init : match.value;
}

private const(MergedAnnotation)* findCheckedAnnotation(return scope const(MergedAnnotation)[] annotations,
        string annotationType)
{
    foreach (ref annotation; annotations)
        if (annotation.error.length)
            throw new AnnotationConfigurationException(annotation.error);
    return findMergedAnnotation(annotations, annotationType);
}

private void verifyEntityBean(T, P)(PersistentEntity!(T, P) entity, Any bean)
{
    if (bean.isNull() || !bean.holds!T())
    {
        const actual = bean.typeName();
        const message = "Bean must be an instance of " ~ entity.getName() ~ "; got " ~ actual;
        throw new IllegalArgumentException(message);
    }
}

private Any copyAccessorBean(T)(Any bean)
{
    static if (is(T == struct))
        return Any.of(bean.get!T);
    else
        return bean;
}

private final class BeanWrapper(T, P) : PersistentPropertyAccessor!(T, P)
{
    private const(Descriptor) descriptor;
    private Any bean;

    this(const(Descriptor) descriptor, Any bean)
    {
        this.descriptor = descriptor;
        this.bean = bean;
    }

    override void setProperty(P property, Any value)
    {
        auto field = findProperty(property);
        if (field.set is null)
        {
            const message = "Property " ~ field.name ~ " is read-only on " ~ descriptor.name;
            throw new MappingException(Nullable!string(message));
        }
        try
            field.set(bean, value);
        catch (Exception failure)
            throw new MappingException(Nullable!string(
                    "Could not write property " ~ field.name ~ " on " ~ descriptor.name), failure);
    }

    override Any getProperty(P property)
    {
        auto field = findProperty(property);
        if (field.get is null)
        {
            const message = "Property " ~ field.name ~ " is write-only on " ~ descriptor.name;
            throw new MappingException(Nullable!string(message));
        }
        try
            return field.get(bean);
        catch (Exception failure)
            throw new MappingException(Nullable!string(
                    "Could not read property " ~ field.name ~ " on " ~ descriptor.name), failure);
    }

    override T getBean()
    {
        return bean.get!T;
    }

    private const(PropertyDescriptor)* findProperty(P property)
    {
        if (property is null)
            throw new IllegalArgumentException("Property must not be null");
        const name = property.getName();
        if (auto field = descriptor.property(name))
            return field;
        throw new MappingException(Nullable!string("No mapped property " ~ name ~ " on " ~ descriptor.name));
    }
}

private struct PropertyRead
{
    Any function(ref Any) @safe read;
    Any function(ref Any) @safe unwrap;
    string property;

    Any get(ref Any bean)
    {
        if (read is null)
        {
            if (property is null)
                return Any.init;
            throw new MappingException(Nullable!string("No mapped reader for property " ~ property));
        }
        auto value = read(bean);
        return unwrap is null ? value : unwrap(value);
    }
}

private final class ModelIdentifierAccessor : TargetAwareIdentifierAccessor
{
    private Any bean;
    private PropertyRead reader;

    this(Any bean, PropertyRead reader)
    {
        super(bean);
        this.bean = bean;
        this.reader = reader;
    }

    override Any getIdentifier()
    {
        return reader.get(bean);
    }
}

private Any readPersistableId(T)(ref Any bean)
{
    auto id = bean.get!T.getId();
    static if (is(typeof(id) == class) || is(typeof(id) == interface))
        return Any.of(id);
    else
        return id.isNull ? Any.init : Any.of(id.get);
}

private bool isNewValue(PropertyRead reader, ClassRef type, ref Any bean)
{
    final switch (primitivePropertyKind(type))
    {
    case PrimitivePropertyKind.boolean:
    case PrimitivePropertyKind.character:
        throw new IllegalArgumentException(
                "Only numeric primitives are supported as identifier / version field types; Got: " ~ type.name);
    case PrimitivePropertyKind.numeric:
        auto value = reader.get(bean);
        if (value.isNull())
            return true;
        const number = value.get!double;
        return !(number <= -1 || number >= 1);
    case PrimitivePropertyKind.reference:
        return reader.get(bean).isNull();
    }
}
