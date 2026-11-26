// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/core/{TypedPropertyPath,PropertyPathUtil}.java
// Copyright 2025-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.core;

import flint.java.lang : IllegalArgumentException, NullPointerException;
public import flint.data.core.type_information : TypeInformation;

@safe:

/// Resolves a property path from a named getter (D-DATA-3).
class PropertyPathUtil
{
    /// The typed path for the getter.
    static TypedPropertyPath!(PropertyOwner!getter, PropertyValue!getter) resolve(alias getter)()
    {
        return TypedPropertyPath!(PropertyOwner!getter, PropertyValue!getter).path!getter();
    }
}

/// A property path resolved from named member references at compile time.
interface TypedPropertyPath(T, P)
{
    package(flint.data) alias Owner = T;

    /// Resolve a zero-argument getter or a record accessor.
    static TypedPropertyPath!(T, P) path(alias getter)()
    {
        enum name = propertySegment!getter;
        static assert(is(T : PropertyOwner!getter) && is(PropertyValue!getter : P),
                "The getter must belong to the path's owner and return its property type");
        return new ResolvedPath!(T, P)(name, (T instance) {
            static if (is(T == class) || is(T == interface))
                if (instance is null)
                    throw new NullPointerException("Property owner must not be null");
            return __traits(getMember, instance, __traits(identifier, getter))();
        });
    }

    /// Resolve a zero-argument getter or a record accessor.
    static TypedPropertyPath!(T, P) of(alias getter)()
    {
        return path!getter();
    }

    /// Resolve the path for an already bound property.
    static TypedPropertyPath!(T, P) of(TypedPropertyPath!(T, P) path)
    {
        if (path is null)
            throw new IllegalArgumentException("Property must not be null");
        return path;
    }

    /// The value on `instance`. A missing intermediate property yields `P.init`.
    P get(T instance);

    /// The dot-separated property names.
    string toDotPath();

    /// Append a getter of this path's value type.
    TypedPropertyPath!(T, PropertyValue!getter) then(alias getter)()
    {
        alias N = PropertyValue!getter;
        auto parent = this;
        auto child = TypedPropertyPath!(P, N).path!getter();
        return new ResolvedPath!(T, N)(toDotPath() ~ "." ~ child.toDotPath(), (T instance) {
            auto intermediate = parent.get(instance);
            static if (is(P == class) || is(P == interface))
                if (intermediate is null)
                    return N.init;
            return child.get(intermediate);
        });
    }
}

private final class ResolvedPath(T, P) : TypedPropertyPath!(T, P)
{
    private string dotPath;
    private P delegate(T) @safe accessor;

    this(string dotPath, P delegate(T) @safe accessor)
    {
        this.dotPath = dotPath;
        this.accessor = accessor;
    }

    override P get(T instance)
    {
        return accessor(instance);
    }

    override string toDotPath()
    {
        return dotPath;
    }
}

package(flint.data) template PropertyOwner(alias getter)
{
    alias PropertyOwner = __traits(parent, getter);
}

package(flint.data) template PropertyValue(alias getter)
{
    alias Owner = PropertyOwner!getter;
    alias PropertyValue = typeof(__traits(getMember, Owner.init, __traits(identifier, getter))());
}

package(flint.data) template propertySegment(alias getter)
{
    static assert(!__traits(isStaticFunction, getter), "Property paths describe instance getters");
    private enum name = __traits(identifier, getter);
    static if (name.length > 3 && name[0 .. 3] == "get")
        enum propertySegment = decapitalize!(name[3 .. $]);
    else static if (is(PropertyValue!getter == bool) && name.length > 2 && name[0 .. 2] == "is")
        enum propertySegment = decapitalize!(name[2 .. $]);
    else
        enum propertySegment = name;
}

private template decapitalize(string name)
{
    enum decapitalize = () {
        import std.uni : isUpper, toLower;
        import std.utf : decode, encode;

        size_t next;
        const first = decode(name, next);
        if (first > 0xFFFF)
            return name;
        if (isUpper(first) && next < name.length)
        {
            auto remainder = next;
            const second = decode(name, remainder);
            if (second <= 0xFFFF && isUpper(second))
                return name;
        }
        const lower = toLower(first);
        if (lower == first)
            return name;
        char[4] bytes;
        const length = encode(bytes, lower);
        return bytes[0 .. length].idup ~ name[next .. $];
    }();
}
