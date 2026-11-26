// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/mapping/context/DefaultPersistentPropertyPathUnitTests.java
// Copyright 2011-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.mapping.context.default_persistent_property_path_tests;

import flint.core.convert.converter : Converter;
import flint.data.mapping : PersistentProperty, PersistentPropertyPath;
import flint.data.mapping.context.default_persistent_property_path : DefaultPersistentPropertyPath;
import flint.java.classref : ClassRef, classOf;
import flint.java.lang : IllegalArgumentException, IllegalStateException;
import flint.java.util : List;
import std.exception : collectException;

@safe:

private interface PathPropertyView : PersistentProperty!PathPropertyView
{
}

private final class PathProperty : PersistentProperty!PathProperty, PathPropertyView
{
    private const string name;

    this(string name)
    {
        this.name = name;
    }

    override string getName()
    {
        return name;
    }

    override ClassRef getType()
    {
        return classOf!string;
    }

    override bool isIdProperty()
    {
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

    override bool isAssociation()
    {
        return false;
    }
}

private alias Path = DefaultPersistentPropertyPath!PathProperty;

private struct Paths
{
    PathProperty first;
    PathProperty second;
    PersistentPropertyPath!PathProperty one;
    PersistentPropertyPath!PathProperty two;
}

private Paths paths()
{
    auto first = new PathProperty("foo");
    auto second = new PathProperty("bar");
    return Paths(first, second, new Path(List!PathProperty.of(first)), new Path(List!PathProperty.of(first, second)));
}

@("rejectsNullProperties")
unittest
{
    assert(collectException!IllegalArgumentException(new Path(null)) !is null);
}

@("usesPropertyNameForSimpleDotPath")
unittest
{
    auto sample = paths();
    assert(sample.two.toDotPath() == "foo.bar");
    assert(sample.two.toPath("/") == "foo/bar");
}

private final class FixedName : Converter!(PathProperty, string)
{
    override string convert(PathProperty)
    {
        return "foo";
    }
}

@("usesConverterToCreatePropertyPath")
unittest
{
    auto sample = paths();
    assert(sample.two.toDotPath(new FixedName()) == "foo.foo");
    assert(sample.two.toPath("/", (PathProperty property) => property.getName()) == "foo/bar");
}

@("returnsCorrectLeafProperty")
unittest
{
    auto sample = paths();
    assert(sample.two.getLeafProperty() is sample.second);
    assert(sample.one.getLeafProperty() is sample.first);
}

@("returnsCorrectBaseProperty")
unittest
{
    auto sample = paths();
    assert(sample.two.getBaseProperty() is sample.first);
    assert(sample.one.getBaseProperty() is sample.first);
}

@("detectsBasePathCorrectly")
unittest
{
    auto sample = paths();
    assert(sample.one.isBasePathOf(sample.two));
    assert(!sample.two.isBasePathOf(sample.one));
}

@("calculatesExtensionCorrectly")
unittest
{
    auto sample = paths();
    auto extension = cast(Path) sample.two.getExtensionForBaseOf(sample.one);
    auto expected = new Path(List!PathProperty.of(sample.second));
    assert(extension == expected && extension.hashCode() == expected.hashCode());
    assert(sample.one.getExtensionForBaseOf(sample.two) is sample.one);
}

@("returnsTheCorrectParentPath")
unittest
{
    auto sample = paths();
    auto parent = cast(Path) sample.two.getParentPath();
    assert(parent == cast(Path) sample.one);
}

@("returnsNullForRootLevelProperty")
unittest
{
    auto sample = paths();
    assert(sample.one.isRootPath());
    assert(sample.one.getParentPath() is null);
}

@("pathReturnsCorrectSize")
unittest
{
    auto sample = paths();
    assert(sample.one.getLength() == 1);
    assert(sample.two.getLength() == 2);
    PathProperty[] traversed;
    foreach (property; sample.two)
        traversed ~= property;
    assert(traversed.length == 2 && traversed[0] is sample.first && traversed[1] is sample.second);
}

@("skipsMappedPropertyNameIfConverterReturnsNull")
unittest
{
    auto sample = paths();
    assert(sample.two.toDotPath((PathProperty source) => string.init) == "");
    assert(sample.two.toPath("/", (PathProperty source) => source is sample.first ? null : "bar") == "bar");
}

@("skipsMappedPropertyNameIfConverterReturnsEmptyStrings")
unittest
{
    auto sample = paths();
    assert(sample.two.toDotPath((PathProperty source) => "") == "");
    assert(sample.two.toPath("/", (PathProperty source) => source is sample.second ? "" : "foo") == "foo");
}

@("throwsExceptionForLeafPropertyOnEmptyPath")
unittest
{
    auto empty = new Path(List!PathProperty.of());
    assert(collectException!IllegalStateException(empty.getLeafProperty()) !is null);
}

@("throwsExceptionForBasePropertyOnEmptyPath")
unittest
{
    auto empty = new Path(List!PathProperty.of());
    assert(collectException!IllegalStateException(empty.getBaseProperty()) !is null);
}

@("path equality follows the properties across concrete bindings")
unittest
{
    auto sample = paths();
    auto other = new DefaultPersistentPropertyPath!PathPropertyView(List!PathPropertyView.of(sample.first,
            sample.second));
    auto path = cast(Path) sample.two;
    assert(path.equals(other) && other.equals(path));
    assert(path.hashCode() == other.hashCode());
}

@("rejects delimiters with no text")
unittest
{
    auto sample = paths();
    assert(collectException!IllegalArgumentException(sample.two.toPath("  ")) !is null);
}
