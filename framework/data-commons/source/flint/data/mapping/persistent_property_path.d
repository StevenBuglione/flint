// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/mapping/PersistentPropertyPath.java
// Copyright 2011-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.mapping.persistent_property_path;

import flint.core.convert.converter : Converter;
import flint.data.mapping : PersistentProperty;
import flint.java.lang : Iterable;

@safe:

/// An ordered path of persistent properties (D-DATA-26).
interface PersistentPropertyPath(P) : Iterable!P if (is(P : PersistentProperty!P))
{
    /// Renders the property names separated by dots.
    string toDotPath();
    /// Renders converted segments separated by dots.
    string toDotPath(Converter!(P, string) converter);
    /// Delegate overload for converted segments (R9).
    string toDotPath(scope string delegate(P) @safe converter);

    /// Renders the property names with the specified delimiter.
    string toPath(string delimiter);
    /// Renders converted segments with the specified delimiter.
    string toPath(string delimiter, Converter!(P, string) converter);
    /// Delegate overload for converted segments (R9).
    string toPath(string delimiter, scope string delegate(P) @safe converter);

    /// The last property in this path.
    P getLeafProperty();
    /// The first property in this path.
    P getBaseProperty();
    /// Whether this path contains exactly one property.
    bool isRootPath();
    /// Whether this path is a prefix of the supplied path.
    bool isBasePathOf(PersistentPropertyPath!P path);
    /// The suffix after a matching base, or this path if the base does not match.
    PersistentPropertyPath!P getExtensionForBaseOf(PersistentPropertyPath!P base);
    /// The path without its final property, or null for a root path.
    PersistentPropertyPath!P getParentPath();
    /// The number of properties in this path.
    int getLength();

    /// Default root check for implementations (R3).
    mixin template Defaults()
    {
        override bool isRootPath()
        {
            return getLength() == 1;
        }
    }
}
