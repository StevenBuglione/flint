// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/mapping/context/InvalidPersistentPropertyPath.java
// Copyright 2015-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.mapping.context;

import flint.beans.propertymatches : PropertyMatches;
import flint.data.core.type_information : TypeInformation, registeredDescriptor;
import flint.data.mapping : MappingException, PersistentPropertyPath;
import flint.data.mapping.model.abstract_persistent_property : AbstractPersistentProperty;
import flint.java.lang : IllegalArgumentException, NullPointerException;
import flint.util : StringUtils;
import std.typecons : Nullable;

@safe:

/// A persistent property path whose next segment could not be resolved.
class InvalidPersistentPropertyPath : MappingException
{
    private const string source;
    private const string unresolvableSegment;
    private const string resolvedPath;
    private TypeInformation type;

    /// Reports an unresolved segment after the given path prefix (D-DATA-29).
    this(P)(string source, TypeInformation type, string unresolvableSegment, PersistentPropertyPath!P resolvedPath)
    {
        if (source is null)
            throw new IllegalArgumentException("Source property path must not be null");
        if (type is null)
            throw new IllegalArgumentException("Type must not be null");
        if (unresolvableSegment is null)
            throw new IllegalArgumentException("Unresolvable segment must not be null");
        if (resolvedPath is null)
            throw new NullPointerException("Resolved path must not be null");

        super(Nullable!string(createMessage(failedType(type, resolvedPath), unresolvableSegment)));
        this.source = source;
        this.type = type;
        this.unresolvableSegment = unresolvableSegment;
        this.resolvedPath = resolvedPath.toDotPath();
    }

    /// The original property path.
    string getSource()
    {
        return source;
    }

    /// The root type used for resolution.
    TypeInformation getType()
    {
        return type;
    }

    /// The segment that could not be resolved.
    string getUnresolvableSegment()
    {
        return unresolvableSegment;
    }

    /// The resolved prefix, in dot notation.
    string getResolvedPath()
    {
        return resolvedPath;
    }
}

private TypeInformation failedType(P)(TypeInformation root, PersistentPropertyPath!P resolved)
{
    if (resolved.getLength() == 0)
        return root;

    auto leaf = cast(AbstractPersistentProperty!P) cast(Object) resolved.getLeafProperty();
    if (leaf is null)
        throw new IllegalArgumentException("Resolved leaf must supply registered type information");
    return leaf.getTypeInformation();
}

private string createMessage(TypeInformation type, string segment)
{
    string suggestions;
    auto descriptor = registeredDescriptor(type);
    if (descriptor !is null && descriptor.properties.length)
    {
        auto names = new string[descriptor.properties.length];
        foreach (index, ref property; descriptor.properties)
            names[index] = property.name;
        auto matches = PropertyMatches.forField(segment, names).getPossibleMatches();
        size_t count;
        foreach (match; matches)
            if (count == 0 || matches[count - 1] != match)
                matches[count++] = match;
        suggestions = StringUtils.arrayToCommaDelimitedString(matches[0 .. count]);
    }

    return "No property '" ~ segment ~ "' found on " ~ type.getType().name ~ "; Did you mean: " ~ suggestions;
}
