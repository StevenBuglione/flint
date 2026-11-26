// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/core/{TypeInformation,TypeDiscoverer}.java
// TypeInformation: Copyright 2008-present the original author or authors.
// TypeDiscoverer: Copyright 2011-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.core.type_information;

import flint.engine.aot.descriptor : Descriptor, DescriptorTable, TypeKind;
import flint.java.classref : ClassRef, classOf;
import flint.java.lang : IllegalArgumentException, IllegalStateException, JavaObject,
    NullPointerException, stringHashCode;

@safe:

/// The type and container shape of an entity or property described by Flint AOT.
interface TypeInformation
{
    /// Look up the pre-registered descriptor for T. Register the descriptor table at startup.
    static TypeInformation of(T)(const(DescriptorTable) descriptors)
    {
        return lookupType(descriptors, classOf!T);
    }

    /// The canonical type token (R4).
    ClassRef getType() const pure nothrow @nogc;

    /// The type of a named property, including a dot-separated path, or null if no such property exists.
    TypeInformation getProperty(string property) const;

    /// The type of a named property, or an error if no such property exists.
    TypeInformation getRequiredProperty(string property) const;

    /// Whether this type describes a collection or array.
    bool isCollectionLike() const nothrow @nogc;

    /// Whether this type describes a map.
    bool isMap() const nothrow @nogc;

    /// An array or collection element, a map key, or a wrapper's component.
    TypeInformation getComponentType() const;

    /// The component type, or an error when the type has no component.
    TypeInformation getRequiredComponentType() const;

    /// The value type for a map, or null for other types.
    TypeInformation getMapValueType() const;

    /// The map value type, or an error when the type has no map value.
    TypeInformation getRequiredMapValueType() const;

    /// The contained value type, or this type for an ordinary value.
    TypeInformation getActualType();

    /// The actual value type, or an error when it cannot be resolved.
    TypeInformation getRequiredActualType();

    /// Whether values of `target` can be assigned to this type.
    bool isAssignableFrom(TypeInformation target) const;

    /// Whether this type is a strict subtype of `type` (R4).
    bool isSubTypeOf(ClassRef type) const nothrow @nogc;

    /// The strict subtype check for a compile-time type.
    bool isSubTypeOf(T)() const nothrow @nogc
    {
        return isSubTypeOf(classOf!T);
    }

    /// Java value equality.
    bool equals(Object other);

    /// A hash consistent with type equality.
    int hashCode();

    /// The canonical type name.
    string toString();
}

private TypeInformation lookupType(const(DescriptorTable) descriptors, ClassRef type)
{
    if (descriptors is null)
        throw new IllegalArgumentException("Descriptor table must not be null");
    return new TypeDiscoverer(descriptors, requireDescriptor(descriptors, type.name));
}

private const(Descriptor) requireDescriptor(const(DescriptorTable) descriptors, string name)
{
    auto descriptor = descriptors.find(name);
    if (descriptor is null)
        throw new IllegalStateException("No Flint AOT descriptor registered for " ~ name);
    return descriptor;
}

private final class TypeDiscoverer : TypeInformation
{
    private const(DescriptorTable) descriptors;
    private const(Descriptor) descriptor;

    this(const(DescriptorTable) descriptors, const(Descriptor) descriptor)
    {
        this.descriptors = descriptors;
        this.descriptor = descriptor;
    }

    override ClassRef getType() const pure nothrow @nogc
    {
        return ClassRef(descriptor.name);
    }

    override TypeInformation getProperty(string property) const
    {
        if (property is null)
            throw new NullPointerException("Property must not be null");

        size_t start;
        string currentType;
        while (true)
        {
            auto current = start == 0 ? descriptor : requireDescriptor(descriptors, currentType);
            size_t end = start;
            while (end < property.length && property[end] != '.')
                end++;

            auto field = current.property(property[start .. end]);
            if (field is null)
                return null;
            if (end == property.length)
                return new TypeDiscoverer(descriptors, requireDescriptor(descriptors, field.type));

            currentType = field.type;
            start = end + 1;
        }
    }

    override TypeInformation getRequiredProperty(string property) const
    {
        auto result = getProperty(property);
        if (result is null)
        {
            const name = descriptor.name;
            throw new IllegalArgumentException("Could not find required property " ~ property ~ " on " ~ name);
        }
        return result;
    }

    override bool isCollectionLike() const nothrow @nogc
    {
        return descriptor.kind == TypeKind.array || descriptor.fromElements !is null;
    }

    override bool isMap() const nothrow @nogc
    {
        return descriptor.keyType.length != 0;
    }

    override TypeInformation getComponentType() const
    {
        return lookupComponent(isMap() ? descriptor.keyType : descriptor.elementType);
    }

    override TypeInformation getRequiredComponentType() const
    {
        return requireType(getComponentType(), "component type");
    }

    override TypeInformation getMapValueType() const
    {
        return isMap() ? lookupComponent(descriptor.elementType) : null;
    }

    override TypeInformation getRequiredMapValueType() const
    {
        return requireType(getMapValueType(), "map value type");
    }

    override TypeInformation getActualType()
    {
        if (isMap())
            return getMapValueType();
        if (isCollectionLike() || descriptor.unwrap !is null)
            return getComponentType();
        return this;
    }

    override TypeInformation getRequiredActualType()
    {
        return requireType(getActualType(), "actual type");
    }

    override bool isAssignableFrom(TypeInformation target) const
    {
        return target !is null && (target.getType() == getType() || target.isSubTypeOf(getType()));
    }

    override bool isSubTypeOf(ClassRef type) const nothrow @nogc
    {
        return type.name != descriptor.name && descriptor.isAssignableTo(type.name);
    }

    private TypeInformation lookupComponent(string name) const
    {
        return name.length ? lookupType(descriptors, ClassRef(name)) : null;
    }

    private TypeInformation requireType(TypeInformation type, string role) const
    {
        if (type is null)
            throw new IllegalStateException("Can't resolve required " ~ role ~ " for " ~ descriptor.name);
        return type;
    }

    override bool equals(Object other)
    {
        auto that = cast(TypeDiscoverer) other;
        return that !is null && descriptor.name == that.descriptor.name;
    }

    override int hashCode()
    {
        return stringHashCode(descriptor.name);
    }

    override string toString()
    {
        return descriptor.name;
    }

    mixin JavaObject;
}
