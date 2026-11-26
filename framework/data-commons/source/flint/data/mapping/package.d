// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/mapping/{Alias,Association,AssociationHandler,IdentifierAccessor,MappingException,PersistentEntity,PersistentProperty,PersistentPropertyAccessor,TargetAwareIdentifierAccessor}.java
// Alias: Copyright 2016-present the original author or authors.
// Association and AssociationHandler: Copyright 2011-present the original author or authors.
// IdentifierAccessor: Copyright 2014-present the original author or authors.
// MappingException, PersistentEntity and PersistentProperty: Copyright 2011-present the original author or authors.
// PersistentPropertyAccessor: Copyright 2014-present the original author or authors.
// TargetAwareIdentifierAccessor: Copyright 2017-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.mapping;

import flint.data.core : TypeInformation;
import flint.data.domain.persistable : NullableId;
import flint.engine.aot.any : Any;
import flint.engine.aot.objects : statelessInstance;
import flint.java.classref : ClassRef, classOf;
import flint.java.lang : IllegalArgumentException, IllegalStateException, Iterable, JavaObject,
    NullPointerException, RuntimeException, String;
import flint.java.util : NoSuchElementException, Objects;
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

package(flint.data) interface PersistentPropertyType
{
    ClassRef getType();
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

/// Describes a property of a persistent entity.
interface PersistentProperty(P) : PersistentPropertyType
{
    /// The name of this property.
    string getName();

    /// Whether this property is the identifier.
    bool isIdProperty();

    /// Whether this property is the optimistic locking version.
    bool isVersionProperty();

    /// Whether this property is excluded from ordinary persistence mapping.
    bool isTransient();
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
    PersistentPropertyType getRequiredIdProperty();
    IdentifierAccessor getIdentifierAccessor(Any bean);
    bool isNew(Any bean);
}

/// Metadata for the persistent properties of a domain entity.
interface PersistentEntity(T, P) : PersistentEntityIdentity, Iterable!P if (is(P : PersistentProperty!P))
{
    /// The entity's qualified name.
    string getName();

    /// The identifier property, or null when no identifier is mapped.
    P getIdProperty();

    /// The identifier property, or an IllegalStateException when no identifier is mapped.
    override P getRequiredIdProperty();

    /// Whether the entity has an identifier property.
    bool hasIdProperty();

    /// The version property, or null when no version is mapped.
    P getVersionProperty();

    /// The version property, or an IllegalStateException when absent.
    P getRequiredVersionProperty();

    /// Whether a version property is mapped.
    bool hasVersionProperty();

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

    /// The named persistent property, or an IllegalStateException when absent.
    P getRequiredPersistentProperty(string name);

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
