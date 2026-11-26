// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/core/ClassTypeInformationUnitTests.java
// Copyright 2025-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module class_type_information_tests;

import flint.data.core : TypeInformation;
import flint.engine.aot.descriptor : DescriptorTable, descriptorOf;
import flint.java.classref : classOf;
import flint.java.lang : IllegalArgumentException, IllegalStateException, NullPointerException;
import std.exception : assertThrown;

@safe:

private struct GenericContent(T)
{
    T content;
}

private struct Wrapper
{
    GenericContent!string wrapped;
}

private final class PropertyGetter
{
    string _name;

    byte[] getName()
    {
        return null;
    }
}

@("discoversTypeForSimpleGenericField")
unittest
{
    auto table = DescriptorTable.withBuiltins();
    table.add(descriptorOf!(GenericContent!string)());
    auto type = TypeInformation.of!(GenericContent!string)(table);
    assert(type.getType() == classOf!(GenericContent!string));
    auto content = type.getProperty("content");
    assert(content.getType() == classOf!string);
    assert(content.getComponentType() is null && content.getMapValueType() is null);
}

@("discoversTypeForNestedGenericField")
unittest
{
    auto table = DescriptorTable.withBuiltins();
    table.add(descriptorOf!Wrapper());
    table.add(descriptorOf!(GenericContent!string)());
    auto type = TypeInformation.of!Wrapper(table);
    auto wrapped = type.getProperty("wrapped");
    assert(wrapped.getType() == classOf!(GenericContent!string));
    assert(wrapped.getProperty("content").getType() == classOf!string);
    assert(type.getRequiredProperty("wrapped.content").getType() == classOf!string);
}

@("handlesPropertyFieldMismatchCorrectly")
unittest
{
    auto table = DescriptorTable.withBuiltins();
    table.add(descriptorOf!PropertyGetter());
    table.add(descriptorOf!(byte[])());
    auto type = TypeInformation.of!PropertyGetter(table);
    assert(type.getRequiredProperty("_name").getType() == classOf!string);
    assert(type.getRequiredProperty("name").getType() == classOf!(byte[]));
}

@("An unknown property and a missing descriptor are different failures")
unittest
{
    auto table = DescriptorTable.withBuiltins();
    table.add(descriptorOf!Wrapper());
    auto type = TypeInformation.of!Wrapper(table);
    assert(type.getProperty("missing.content") is null);
    assert(type.getProperty("") is null);
    assertThrown!NullPointerException(type.getProperty(null));
    assertThrown!IllegalArgumentException(type.getRequiredProperty("missing"));
    assertThrown!IllegalStateException(type.getProperty("wrapped.content"));
}
