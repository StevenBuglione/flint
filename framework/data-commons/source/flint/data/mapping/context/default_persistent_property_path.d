// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/mapping/context/DefaultPersistentPropertyPath.java
// Copyright 2011-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.mapping.context.default_persistent_property_path;

import flint.core.convert.converter : Converter;
import flint.data.mapping : PersistentProperty, PersistentPropertyPath;
import flint.java.lang : IllegalArgumentException, IllegalStateException, JavaObject;
import flint.java.util : Iterator, List, Objects;
import flint.util : StringUtils;

@safe:

// Equality compares the resolved properties across bindings of the same path class.
private interface PathProperties
{
    int getLength();
    PersistentProperty!() propertyAt(int index);
}

package final class DefaultPersistentPropertyPath(P) : PersistentPropertyPath!P,
    PathProperties if (is(P : PersistentProperty!P))
{
    private List!P properties;

    this(List!P properties)
    {
        if (properties is null)
            throw new IllegalArgumentException("Properties must not be null");
        this.properties = properties;
    }

    mixin PersistentPropertyPath!P.Defaults;
    mixin JavaObject;

    override string toDotPath()
    {
        return toPath(".");
    }

    override string toDotPath(Converter!(P, string) converter)
    {
        return toPath(".", converter);
    }

    override string toDotPath(scope string delegate(P) @safe converter)
    {
        return toPath(".", converter);
    }

    override string toPath(string delimiter)
    {
        return toPath(delimiter, (P property) => property.getName());
    }

    override string toPath(string delimiter, Converter!(P, string) converter)
    {
        return toPath(delimiter, converter is null ? null : &converter.convert);
    }

    override string toPath(string delimiter, scope string delegate(P) @safe converter)
    {
        if (!StringUtils.hasText(delimiter))
            throw new IllegalArgumentException("Delimiter must not be null or empty");
        if (converter is null)
            throw new IllegalArgumentException("Converter must not be null");

        char[] result;
        foreach (property; properties)
        {
            const segment = converter(property);
            if (segment.length == 0)
                continue;
            if (result.length != 0)
                result ~= delimiter;
            result ~= segment;
        }
        return result.length ? result.idup : "";
    }

    override P getLeafProperty()
    {
        requireProperties();
        return properties.get(getLength() - 1);
    }

    override P getBaseProperty()
    {
        requireProperties();
        return properties.get(0);
    }

    private void requireProperties()
    {
        if (properties.isEmpty())
            throw new IllegalStateException("Empty PersistentPropertyPath should not exist");
    }

    override bool isBasePathOf(PersistentPropertyPath!P path)
    {
        if (path is null)
            throw new IllegalArgumentException("PersistentPropertyPath must not be null");

        auto candidate = path.iterator();
        foreach (property; properties)
            if (!candidate.hasNext() || !Objects.equals(property, candidate.next()))
                return false;
        return true;
    }

    override PersistentPropertyPath!P getExtensionForBaseOf(PersistentPropertyPath!P base)
    {
        if (!Objects.requireNonNull(base, "Base path must not be null").isBasePathOf(this))
            return this;
        return new DefaultPersistentPropertyPath(properties.subList(base.getLength(), getLength()));
    }

    override PersistentPropertyPath!P getParentPath()
    {
        const length = getLength();
        return length == 1 ? null : new DefaultPersistentPropertyPath(properties.subList(0, length - 1));
    }

    override int getLength()
    {
        return properties.size();
    }

    override Iterator!P iterator()
    {
        return properties.iterator();
    }

    override void forEach(void delegate(P) @safe action)
    {
        properties.forEach(action);
    }

    override int opApply(scope int delegate(P) @safe visitor)
    {
        return properties.opApply(visitor);
    }

    override PersistentProperty!() propertyAt(int index)
    {
        return properties.get(index);
    }

    bool equals(Object other)
    {
        if (other is this)
            return true;
        auto path = cast(PathProperties) other;
        if (path is null || path.getLength() != getLength())
            return false;

        foreach (index; 0 .. getLength())
            if (!Objects.equals(propertyAt(index), path.propertyAt(index)))
                return false;
        return true;
    }

    int hashCode()
    {
        return properties.hashCode();
    }

    override string toString()
    {
        return toDotPath();
    }
}
