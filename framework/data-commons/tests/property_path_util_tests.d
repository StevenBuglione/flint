// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/core/PropertyPathUtilUnitTests.java
// Copyright 2025-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module property_path_util_tests;

import flint.data.core : PropertyPathUtil;

@safe:

private final class Person
{
    string name;

    string getName()
    {
        return name;
    }
}

@("shouldResolvePropertyPath")
unittest
{
    auto path = PropertyPathUtil.resolve!(Person.getName)();
    assert(path.toDotPath() == "name");
}

@("resolvedPathShouldDelegatePropertyAccess")
unittest
{
    auto path = PropertyPathUtil.resolve!(Person.getName)();
    auto person = new Person();
    person.name = "Walter";
    assert(path.toDotPath() == "name");
    assert(path.get(person) == "Walter");

    person.name = "Jean";
    assert(path.get(person) == "Jean");
}
