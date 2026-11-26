// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/core/TypeDiscovererUnitTests.java
// Copyright 2025-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module type_discoverer_tests;

import flint.data.core : TypeInformation;
import flint.engine.aot.descriptor : DescriptorTable, descriptorOf;
import flint.java.classref : classOf;
import flint.java.lang : IllegalArgumentException, IllegalStateException;
import flint.java.util : ArrayList, Collection, HashMap, List, Optional, Set;
import std.exception : assertThrown;

@safe:

private final class CustomMap : HashMap!(string, long)
{
}

private final class CustomCollection : ArrayList!string
{
}

@("isNotEqualIfTypesDiffer")
unittest
{
    auto table = DescriptorTable.withBuiltins();
    table.add(descriptorOf!Object());
    auto objectType = TypeInformation.of!Object(table);
    auto stringType = TypeInformation.of!string(table);
    assert(!objectType.equals(cast(Object) stringType));
    assert(stringType.equals(cast(Object) TypeInformation.of!string(table)));
    assert(stringType.getType() == classOf!string);
}

@("returnsComponentAndValueTypesForMapExtensions")
unittest
{
    auto table = DescriptorTable.withBuiltins();
    table.add(descriptorOf!CustomMap());
    auto type = TypeInformation.of!CustomMap(table);
    assert(type.isMap() && !type.isCollectionLike());
    assert(type.getComponentType().getType() == classOf!string);
    assert(type.getMapValueType().getType() == classOf!long);
    assert(type.getActualType().getType() == classOf!long);
}

@("returnsComponentTypeForCollectionExtension")
unittest
{
    auto table = DescriptorTable.withBuiltins();
    table.add(descriptorOf!CustomCollection());
    auto type = TypeInformation.of!CustomCollection(table);
    assert(type.isCollectionLike() && !type.isMap());
    assert(type.getComponentType().getType() == classOf!string);
    assert(type.getActualType().getType() == classOf!string);
}

@("returnsComponentTypeForArrays")
unittest
{
    auto table = DescriptorTable.withBuiltins();
    table.add(descriptorOf!(string[])());
    auto type = TypeInformation.of!(string[])(table);
    assert(type.isCollectionLike());
    assert(type.getType() == classOf!(string[]));
    assert(type.getComponentType().getType() == classOf!string);
}

@("detectsSubTypes")
unittest
{
    auto table = DescriptorTable.withBuiltins();
    table.add(descriptorOf!(Set!string)());
    table.add(descriptorOf!(Collection!string)());
    auto type = TypeInformation.of!(Set!string)(table);
    assert(type.isSubTypeOf!(Collection!string)());
    assert(!type.isSubTypeOf!(Set!string)());
    assert(!type.isSubTypeOf!string());
    assert(TypeInformation.of!(Collection!string)(table).isAssignableFrom(type));
}

@("An optional has an actual type but is not a collection")
unittest
{
    auto table = DescriptorTable.withBuiltins();
    table.add(descriptorOf!(Optional!long)());
    auto type = TypeInformation.of!(Optional!long)(table);
    assert(!type.isCollectionLike() && !type.isMap());
    assert(type.getComponentType().getType() == classOf!long);
    assert(type.getActualType().getType() == classOf!long);
}

@("A missing descriptor is reported at the first lookup")
unittest
{
    auto table = new DescriptorTable();
    table.add(descriptorOf!(List!long)());
    assertThrown!IllegalArgumentException(TypeInformation.of!string(null));
    assertThrown!IllegalStateException(TypeInformation.of!string(table));
    assertThrown!IllegalStateException(TypeInformation.of!(List!long)(table).getComponentType());
}

@("Required type accessors report an absent type")
unittest
{
    auto table = DescriptorTable.withBuiltins();
    table.add(descriptorOf!(HashMap!(string, long))());
    auto value = TypeInformation.of!long(table);
    assert(value.getComponentType() is null && value.getMapValueType() is null);
    assertThrown!IllegalStateException(value.getRequiredComponentType());
    assertThrown!IllegalStateException(value.getRequiredMapValueType());
    assert(value.getRequiredActualType() is value);

    auto map = TypeInformation.of!(HashMap!(string, long))(table);
    assert(map.getRequiredComponentType().getType() == classOf!string);
    assert(map.getRequiredMapValueType().getType() == classOf!long);
    assert(map.getRequiredActualType().getType() == classOf!long);
}
