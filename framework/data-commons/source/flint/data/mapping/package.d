// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/mapping/{Alias,Association,AssociationHandler,IdentifierAccessor,InstanceCreatorMetadata,MappingException,Parameter,PersistentEntity,PersistentProperty,PersistentPropertyAccessor,PreferredConstructor,PropertyHandler,TargetAwareIdentifierAccessor}.java
// Alias: Copyright 2016-present the original author or authors.
// Association, AssociationHandler and PropertyHandler: Copyright 2011-present the original author or authors.
// IdentifierAccessor: Copyright 2014-present the original author or authors.
// MappingException, PersistentEntity, PersistentProperty and PreferredConstructor: Copyright 2011-present the original author or authors.
// InstanceCreatorMetadata and Parameter: Copyright 2021-present the original author or authors.
// PersistentPropertyAccessor: Copyright 2014-present the original author or authors.
// TargetAwareIdentifierAccessor: Copyright 2017-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.mapping;

import flint.beans.factory.annotation : Value;
import flint.core.annotation.types : MergedAnnotations, SearchStrategy;
import flint.data.annotation : PersistenceCreator, Transient;
import flint.data.core : TypeInformation;
import flint.data.domain.persistable : NullableId;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : ConstructorDescriptor, MergedAnnotation, findAnnotation;
import flint.engine.aot.objects : statelessInstance;
import flint.java.classref : ClassRef, classOf;
import flint.java.lang : IllegalArgumentException, IllegalStateException, Iterable, JavaObject,
    NullPointerException, RuntimeException, String;
import flint.java.util : List, NoSuchElementException, Objects;
import flint.util : StringUtils;
import std.typecons : Nullable;

@safe:

/// Access to the identifier of an entity.
interface IdentifierAccessor
{
    /// The identifier or a null value when the entity has none.
    Any getIdentifier();

    /// The identifier, or an IllegalStateException if it is absent.
    Any getRequiredIdentifier();

    /// Default missing-identifier check for implementations (R3).
    mixin template Defaults()
    {
        imported!"flint.engine.aot.any".Any getRequiredIdentifier()
        {
            auto identifier = getIdentifier();
            if (identifier.isNull())
                throw new imported!"flint.java.lang".IllegalStateException("Could not obtain identifier");
            return identifier;
        }
    }
}

/// Adds the target's rendering to an absent-identifier error.
abstract class TargetAwareIdentifierAccessor : IdentifierAccessor
{
    private Any target;

    /// Captures the target for a missing-identifier diagnostic.
    this(Any target)
    {
        this.target = target;
    }

    override Any getRequiredIdentifier()
    {
        auto identifier = getIdentifier();
        if (identifier.isNull())
            throw new IllegalStateException(String.format("Could not obtain identifier from %s", target));
        return identifier;
    }
}

/// Reports a failure in persistence mapping.
class MappingException : RuntimeException
{
    /// Constructs the exception with an optional detail message.
    this(Nullable!string message) pure nothrow
    {
        super(message.isNull ? null : message.get);
    }

    /// Constructs the exception with an optional detail message and an initialized cause.
    this(Nullable!string message, Throwable cause)
    {
        super(message.isNull ? null : message.get, cause);
        // The two-argument Java constructor initializes even a null cause.
        if (cause is null)
            super.initCause(null);
    }
}

package(flint.data) enum PrimitivePropertyKind
{
    reference,
    numeric,
    boolean,
    character,
}

package(flint.data) PrimitivePropertyKind primitivePropertyKind(ClassRef type) pure nothrow @nogc
{
    switch (type.name)
    {
    case classOf!byte.name:
    case classOf!short.name:
    case classOf!int.name:
    case classOf!long.name:
    case classOf!float.name:
    case classOf!double.name:
        return PrimitivePropertyKind.numeric;
    case classOf!bool.name:
        return PrimitivePropertyKind.boolean;
    case classOf!char.name:
    case classOf!wchar.name:
    case classOf!dchar.name:
        return PrimitivePropertyKind.character;
    default:
        return PrimitivePropertyKind.reference;
    }
}

/// Shared metadata of a persistent property when its concrete property type is unspecified.
interface PersistentProperty()
{
    /// The name of this property.
    string getName();

    /// The declared property type.
    ClassRef getType();

    /// Whether this property is the identifier.
    bool isIdProperty();

    /// Whether this property is the optimistic locking version.
    bool isVersionProperty();

    /// Whether this property is excluded from ordinary persistence mapping.
    bool isTransient();

    /// Whether this property denotes an association.
    bool isAssociation();
}

/// Describes a persistent property in APIs that retain its concrete property type.
interface PersistentProperty(P) : PersistentProperty!()
{
}

/// The two persistent properties connected by an association.
class Association(P) if (is(P : PersistentProperty!P))
{
    private P inverse;
    private P obverse;

    /// Creates an association whose obverse may be null.
    this(P inverse, P obverse)
    {
        this.inverse = inverse;
        this.obverse = obverse;
    }

    /// The inverse property.
    P getInverse()
    {
        return inverse;
    }

    /// The obverse property, or null when absent.
    P getObverse()
    {
        return obverse;
    }
}

/// Processes an association of persistent properties.
interface AssociationHandler(P) if (is(P : PersistentProperty!P))
{
    /// Invokes the handler for the supplied association.
    void doWithAssociation(Association!P association);
}

/// Processes a persistent property.
interface PropertyHandler(P) if (is(P : PersistentProperty!P))
{
    /// Invokes the handler for the supplied property.
    void doWithPersistentProperty(P property);
}

/// Access to the persistent properties of a mapped bean.
interface PersistentPropertyAccessor(T, P) if (is(P : PersistentProperty!P))
{
    /// Writes a property from its descriptor's erased value representation.
    void setProperty(P property, Any value);

    /// Reads a property into its descriptor's erased value representation.
    Any getProperty(P property);

    /// The current bean, including any changes made through this accessor.
    T getBean();
}

// The repository adapter uses the same metadata without retaining the property type parameter.
package(flint.data) interface PersistentEntityIdentity
{
    ClassRef getType();
    PersistentProperty!() getRequiredIdProperty();
    IdentifierAccessor getIdentifierAccessor(Any bean);
    bool isNew(Any bean);
}

/// Metadata for the persistent properties of a domain entity.
interface PersistentEntity(T, P) : PersistentEntityIdentity, Iterable!P if (is(P : PersistentProperty!P))
{
    /// The entity's qualified name.
    string getName();

    /// The registered creator metadata, or null when no creator is selected.
    InstanceCreatorMetadata!(T, P) getInstanceCreatorMetadata();

    /// Whether the property is supplied by the selected creator.
    bool isCreatorArgument(PersistentProperty!() property);

    /// The identifier property, or null when no identifier is mapped.
    P getIdProperty();

    /// The identifier property, or an IllegalStateException when no identifier is mapped.
    override P getRequiredIdProperty();

    /// Whether the entity has an identifier property.
    bool hasIdProperty();

    /// Whether the supplied property matches the entity's identifier.
    bool isIdProperty(PersistentProperty!() property);

    /// The version property, or null when no version is mapped.
    P getVersionProperty();

    /// The version property, or an IllegalStateException when absent.
    P getRequiredVersionProperty();

    /// Whether a version property is mapped.
    bool hasVersionProperty();

    /// Whether the supplied property matches the entity's version.
    bool isVersionProperty(PersistentProperty!() property);

    /// The first persistent property with the given name, or null.
    P getPersistentProperty(string name);

    /// The first persistent property with the given annotation, or null.
    P getPersistentProperty(ClassRef annotationType);

    /// The persistent properties with the given annotation, in property order.
    Iterable!P getPersistentProperties(ClassRef annotationType);

    /// Invokes the handler for every registered association.
    void doWithAssociations(AssociationHandler!P handler);

    /// Delegate overload of association traversal (R9).
    void doWithAssociations(scope void delegate(Association!P) @safe handler);

    /// Invokes the handler for ordinary persistent properties.
    void doWithProperties(PropertyHandler!P handler);

    /// Delegate overload of persistent-property traversal (R9).
    void doWithProperties(scope void delegate(P) @safe handler);

    /// Visits ordinary properties and then the inverse properties of associations.
    void doWithAll(PropertyHandler!P handler);

    /// Delegate overload of combined traversal (R9).
    void doWithAll(scope void delegate(P) @safe handler);

    /// The named persistent property, or an IllegalStateException when absent.
    P getRequiredPersistentProperty(string name);

    /// The registered transient property with the given name, or null.
    P getTransientProperty(string name);

    /// Whether the given name denotes a transient property.
    bool isTransient(string name);

    /// The metadata for the entity's domain type.
    TypeInformation getTypeInformation();

    /// The registered type alias, or Alias.NONE when absent.
    Alias getTypeAlias();

    /// The merged annotation, or an empty Any when absent.
    const(Any) findAnnotation(ClassRef annotationType);

    /// The merged annotation, or an IllegalStateException when absent.
    const(Any) getRequiredAnnotation(ClassRef annotationType);

    /// Whether the given annotation is present in the type hierarchy.
    bool isAnnotationPresent(ClassRef annotationType);

    /// Whether the entity is marked as immutable.
    bool isImmutable();

    /// Whether a registered property needs to be populated after creation.
    bool requiresPropertyPopulation();

    /// Creates an accessor for a compatible bean.
    PersistentPropertyAccessor!(T, P) getPropertyAccessor(Any bean);

    /// Supplies the metadata lookup defaults (R3).
    mixin template Defaults(PropertyType = P)
    {
        PropertyType getRequiredIdProperty()
        {
            auto identifier = getIdProperty();
            if (identifier is null)
                throw new imported!"flint.java.lang".IllegalStateException(
                        "Required identifier property not found for " ~ getType().name);
            return identifier;
        }

        PropertyType getRequiredVersionProperty()
        {
            auto versionProperty = getVersionProperty();
            if (versionProperty is null)
                throw new imported!"flint.java.lang".IllegalStateException(
                        "Required version property not found for " ~ getType().name);
            return versionProperty;
        }

        PropertyType getRequiredPersistentProperty(string name)
        {
            auto property = this.getPersistentProperty(name);
            if (property is null)
                throw new imported!"flint.java.lang".IllegalStateException("Required property " ~ (name is null
                        ? "null" : name) ~ " not found for " ~ getType().name);
            return property;
        }

        PropertyType getPersistentProperty(ClassRef annotationType)
        {
            auto matches = getPersistentProperties(annotationType).iterator();
            return matches.hasNext() ? matches.next() : null;
        }

        const(Any) getRequiredAnnotation(ClassRef annotationType)
        {
            const annotation = findAnnotation(annotationType);
            if (annotation.isNull())
                throw new imported!"flint.java.lang".IllegalStateException(
                        "Required annotation " ~ annotationType.name ~ " not found for " ~ getType().name);
            return annotation;
        }

        void doWithAll(PropertyHandler!P handler)
        {
            if (handler is null)
                throw new imported!"flint.java.lang".IllegalArgumentException("PropertyHandler must not be null");
            doWithAll(&handler.doWithPersistentProperty);
        }

        void doWithAll(scope void delegate(P) @safe handler)
        {
            doWithProperties(handler);
            doWithAssociations((association) { handler(association.getInverse()); });
        }
    }
}

/// Creator queries that do not require the concrete entity and property types.
interface InstanceCreatorMetadata()
{
    /// Whether the creator receives this persistent property.
    bool isCreatorParameter(PersistentProperty!() property);

    /// The number of parameters the creator accepts.
    int getParameterCount();

    /// Whether this creator accepts any parameters.
    bool hasParameters();
}

/// Describes the parameters used to create instances of a persistent entity.
interface InstanceCreatorMetadata(T, P) : InstanceCreatorMetadata!() if (is(P : PersistentProperty!P))
{
    /// Whether the parameter represents a parent or receiver.
    bool isParentParameter(Parameter!(T, P) parameter);

    /// The creator's parameters in declaration order.
    List!(Parameter!(T, P)) getParameters();

    /// Supplies the default parameter queries (R3).
    mixin template Defaults(ParameterType = Parameter!(T, P))
    {
        bool isParentParameter(ParameterType)
        {
            return false;
        }

        int getParameterCount()
        {
            return getParameters().size();
        }

        bool hasParameters()
        {
            return !getParameters().isEmpty();
        }
    }
}

// Shares value equality across parameter bindings (R11).
private abstract class ParameterValue
{
    private Nullable!string name;
    private TypeInformation type;
    private Nullable!string expression;

    protected abstract Object owningEntity();

    /// Whether the name, declared type, expression and owning entity are equal.
    bool equals(Object other)
    {
        if (this is other)
            return true;
        auto that = cast(ParameterValue) other;
        return that !is null && name == that.name && type.equals(cast(Object) that.type)
            && expression == that.expression && Objects.equals(owningEntity(), that.owningEntity());
    }

    /// Hashes the same metadata used by equality.
    int hashCode()
    {
        return Objects.hash(name.get(string.init), type, expression.get(string.init), owningEntity());
    }

    mixin JavaObject;
}

/// Metadata for a parameter of an entity creator.
class Parameter(T, P) : ParameterValue if (is(P : PersistentProperty!P))
{
    private MergedAnnotations annotations;
    private PersistentEntity!(T, P) entity;

    /// Creates a parameter with a nullable name and its registered metadata.
    this(Nullable!string name, TypeInformation type, const(MergedAnnotation)[] annotations,
            PersistentEntity!(T, P) entity)
    {
        if (type is null)
            throw new IllegalArgumentException("Type must not be null");
        this.name = name;
        this.type = type;
        this.annotations = MergedAnnotations.from(annotations, SearchStrategy.DIRECT);
        this.entity = entity;
        const value = this.annotations.get!Value();
        if (value.isPresent())
        {
            const text = value.synthesize().value;
            if (StringUtils.hasText(text))
                expression = Nullable!string(text);
        }
    }

    /// The parameter name, if available.
    Nullable!string getName()
    {
        return name;
    }

    /// Whether this parameter has a name.
    bool hasName()
    {
        return !name.isNull;
    }

    /// The name, or an IllegalStateException when no name is present.
    string getRequiredName()
    {
        if (!hasName())
            throw new IllegalStateException("No name associated with this parameter");
        return name.get;
    }

    /// The declared parameter type information.
    TypeInformation getType()
    {
        return type;
    }

    /// The parameter's raw type token (R4).
    ClassRef getRawType()
    {
        return type.getType();
    }

    /// The registered merged annotations on this parameter.
    MergedAnnotations getAnnotations()
    {
        return annotations;
    }

    /// The value expression, if present.
    Nullable!string getValueExpression()
    {
        return expression;
    }

    /// The value expression, if present, through the Spring compatibility name.
    Nullable!string getSpelExpression()
    {
        return getValueExpression();
    }

    /// Whether this parameter has a value expression.
    bool hasValueExpression()
    {
        return !expression.isNull;
    }

    /// The value expression, or an IllegalStateException when absent.
    string getRequiredValueExpression()
    {
        if (!hasValueExpression())
            throw new IllegalStateException("No expression associated with this parameter");
        return expression.get;
    }

    /// Whether the parameter or its matching property is transient.
    bool isTransient()
    {
        return annotations.isPresent!Transient() || (entity !is null && hasName() && entity.isTransient(name.get));
    }

    protected override final Object owningEntity()
    {
        return cast(Object) entity;
    }

    package(flint.data) bool maps(PersistentProperty!() property)
    {
        return property !is null && entity !is null && hasName() && Objects.equals(property,
                entity.getPersistentProperty(name.get));
    }
}

/// The selected constructor and its parameters for a persistent entity.
final class PreferredConstructor(T, P) : InstanceCreatorMetadata!(T, P) if (is(P : PersistentProperty!P))
{
    private const(ConstructorDescriptor) constructor;
    private List!(Parameter!(T, P)) parameters;

    /// Captures a registered constructor and its parameters in declaration order (D-DATA-23).
    this(const(ConstructorDescriptor) constructor, Parameter!(T, P)[] parameters...)
    {
        this(constructor, List!(Parameter!(T, P)).of(parameters));
    }

    package(flint.data) this(const(ConstructorDescriptor) constructor, List!(Parameter!(T, P)) parameters)
    {
        this.constructor = constructor;
        this.parameters = parameters;
    }

    /// The read-only registered constructor descriptor (D-DATA-23).
    const(ConstructorDescriptor) getConstructor()
    {
        return constructor;
    }

    /// Whether the selected constructor takes no arguments.
    bool isNoArgConstructor()
    {
        return !hasParameters();
    }

    /// Whether PersistenceCreator marks the selected constructor.
    bool isExplicitlyAnnotated() const nothrow @nogc
    {
        return findAnnotation(constructor.annotations, classOf!PersistenceCreator.name) !is null;
    }

    mixin InstanceCreatorMetadata!(T, P).Defaults;

    override bool isCreatorParameter(PersistentProperty!() property)
    {
        foreach (parameter; parameters)
            if (parameter.maps(property))
                return true;
        return false;
    }

    override List!(Parameter!(T, P)) getParameters()
    {
        return parameters;
    }
}

/// An immutable, optionally present type alias.
abstract class Alias
{
    private this() pure nothrow @nogc
    {
    }

    /// The shared absent alias (R17).
    static Alias NONE() nothrow @nogc
    {
        return statelessInstance!EmptyAlias();
    }

    /// Wraps a present alias.
    static Alias of(Any value)
    {
        if (value.isNull())
            throw new IllegalArgumentException("Alias must not be null");
        return new PresentAlias(value);
    }

    /// Wraps a present alias or returns the shared empty instance.
    static Alias ofNullable(Any value)
    {
        return value.isNull() ? NONE : new PresentAlias(value);
    }

    /// The shared absent alias.
    static Alias empty() nothrow @nogc
    {
        return NONE;
    }

    /// Whether this alias has a value that differs from the other alias.
    bool isPresentButDifferent(Alias other)
    {
        if (other is null)
            throw new IllegalArgumentException("Other alias must not be null");
        auto value = getValue();
        return !value.isNull() && !equalAliasValues(value, other.getValue());
    }

    /// Whether this alias has the specified value.
    bool hasValue(Any that)
    {
        auto value = getValue();
        return !value.isNull() && equalAliasValues(value, that);
    }

    /// Whether both aliases have the same present value.
    bool hasSamePresentValueAs(Alias other)
    {
        auto value = getValue();
        if (value.isNull())
            return false;
        if (other is null)
            throw new NullPointerException("Other alias must not be null");
        return equalAliasValues(value, other.getValue());
    }

    /// Whether an alias value is present.
    bool isPresent() nothrow @nogc
    {
        return !getValue().isNull();
    }

    /// Whether the alias is absent.
    bool isEmpty() nothrow @nogc
    {
        return getValue().isNull();
    }

    /// The value if it has the requested type, with ordinary subtype checks for references.
    NullableId!T mapTyped(T)()
    {
        auto value = getValue();
        static if (is(T == Any))
            return value.isNull() ? NullableId!T.init : NullableId!T(value);
        else static if (is(T == class) || is(T == interface))
            return cast(T) value.asObject();
        else
            return value.isNull() || value.typeName() != classOf!T.name ? NullableId!T.init
                : NullableId!T(value.get!T);
    }

    /// The alias value, or Any.init when absent.
    abstract Any getValue() nothrow @nogc;

    /// The alias value, or a NoSuchElementException when absent.
    Any getRequiredValue()
    {
        auto value = getValue();
        if (value.isNull())
            throw new NoSuchElementException("No value present");
        return value;
    }

    /// Value equality, including shared absence.
    bool equals(Object other)
    {
        if (this is other)
            return true;
        auto aliasValue = cast(Alias) other;
        return aliasValue !is null && equalAliasValues(getValue(), aliasValue.getValue());
    }

    /// The hash of the held value, or zero for absence.
    int hashCode()
    {
        auto value = getValue();
        if (value.isNull())
            return 0;
        if (auto object = value.asObject())
            return Objects.hashCode(object);
        return hashAliasValue(value);
    }

    /// The value's Java string representation, or NONE for absence.
    override string toString()
    {
        auto value = getValue();
        if (value.isNull())
            return "NONE";
        if (value.typeName() == "string")
            return value.get!string;
        return String.format("%s", value);
    }

    mixin JavaObject;
}

private final class EmptyAlias : Alias
{
    override Any getValue() nothrow @nogc
    {
        return Any.init;
    }
}

private final class PresentAlias : Alias
{
    private Any value;

    this(Any value) nothrow @nogc
    {
        this.value = value;
    }

    override Any getValue() nothrow @nogc
    {
        return value;
    }
}

private bool equalAliasValues(Any left, Any right)
{
    if (left.isNull() || right.isNull())
        return left.isNull() && right.isNull();
    auto lhs = left.asObject();
    auto rhs = right.asObject();
    if (lhs !is null || rhs !is null)
        return Objects.equals(lhs, rhs);
    const type = left.typeName();
    if (type != right.typeName())
        return false;
    if (type == "float" || type == "double")
    {
        const x = left.get!double;
        const y = right.get!double;
        return x != x ? y != y : x == y && (x != 0 || Objects.hashCode(x) == Objects.hashCode(y));
    }
    return left == right;
}

private int hashAliasValue(Any value)
{
    switch (value.typeName())
    {
    case "string":
        return Objects.hashCode(value.get!string);
    case "bool":
        return Objects.hashCode(value.get!bool);
    case "long", "ulong":
        return Objects.hashCode(value.typeName() == "long"
                ? cast(ulong) value.get!long : value.get!ulong);
    case "double":
        return Objects.hashCode(value.get!double);
    case "float":
        return hashAliasFloat(value.get!float);
    default:
        if (value.holds!long())
            return cast(int) value.get!long;
        if (value.holds!dchar())
            return cast(int) value.get!dchar;
        return cast(int) value.toHash();
    }
}

private int hashAliasFloat(float number) pure nothrow @nogc
{
    if (number != number)
        return 0x7fc0_0000;
    union FloatBits
    {
        float number;
        int bits;
    }

    FloatBits bits;
    bits.number = number;
    return bits.bits;
}
