// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/domain/SortUnitTests.java
// Copyright 2008-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.typed_sort_tests;

import flint.data.core : TypedPropertyPath;
import flint.data.domain : Sort;
import flint.java.util : List, Map;

@safe:

private alias Order = Sort.Order;
private alias Direction = Sort.Direction;

private class Person
{
    string getFirstName()
    {
        return "Ada";
    }

    string getLastName()
    {
        return "Lovelace";
    }

    bool isActive()
    {
        return true;
    }

    string getURL()
    {
        return "example";
    }

    int getÉtage()
    {
        return 1;
    }

    static string getStaticName()
    {
        return "example";
    }
}

private struct PersonHolder
{
    Person value;

    Person person()
    {
        return value;
    }
}

private class Sample
{
    Person getNested()
    {
        assert(false, "A sort declaration must not invoke the getter");
    }

    List!Person getNesteds()
    {
        assert(false, "A sort declaration must not read the collection");
    }

    Map!(string, Person) getNames()
    {
        assert(false, "A sort declaration must not read the map");
    }

    int getCount()
    {
        return 0;
    }
}

private alias NamePath = TypedPropertyPath!(Person, string);

@("SortUnitTests.appliesDefaultForOrderForProperty")
unittest
{
    auto path = NamePath.path!(Person.getFirstName)();
    assert(Sort.by(path).iterator().next().getDirection() == Sort.DEFAULT_DIRECTION);
}

@("SortUnitTests.appliesPropertyPath")
unittest
{
    auto name = NamePath.path!(Person.getFirstName)();
    auto nested = TypedPropertyPath!(PersonHolder, Person).path!(PersonHolder.person)().then!(Person.getFirstName)();

    assert(Sort.by(name).iterator().next().getProperty() == "firstName");
    assert(Sort.by(nested).iterator().next().getProperty() == "person.firstName");
    assert(nested.get(PersonHolder(new Person())) == "Ada");
    assert(nested.get(PersonHolder.init) is null);
}

@("SortUnitTests.appliesPropertyPaths")
unittest
{
    auto first = NamePath.path!(Person.getFirstName)();
    auto last = NamePath.path!(Person.getLastName)();
    assert(Sort.by(first, last) == Sort.by("firstName", "lastName"));
    assert(Sort.by(Direction.DESC, first, last) == Sort.by(Direction.DESC, "firstName", "lastName"));
}

@("SortUnitTests.appliesPropertyPathsWithOrders")
unittest
{
    auto first = NamePath.path!(Person.getFirstName)();
    auto last = NamePath.path!(Person.getLastName)();
    assert(Sort.by(Order.asc(first), Order.desc(last)) == Sort.by(Order.asc("firstName"), Order.desc("lastName")));
}

@("SortUnitTests.orderFactoryMethodsConsiderPropertyPath")
unittest
{
    auto path = NamePath.path!(Person.getFirstName)();
    assert(Order.by(path) == Order.by("firstName"));
    assert(Order.asc(path) == Order.asc("firstName"));
    assert(Order.desc(path) == Order.desc("firstName"));
}

@("SortUnitTests.createsNewOrderForDifferentPropertyPath")
unittest
{
    auto path = NamePath.path!(Person.getFirstName)();
    auto source = Order.desc("foo").nullsFirst().ignoreCase();
    auto result = source.withProperty(path);

    assert(result.getProperty() == "firstName");
    assert(result.getDirection() == source.getDirection());
    assert(result.getNullHandling() == source.getNullHandling());
    assert(result.isIgnoreCase() == source.isIgnoreCase());
}

@("SortUnitTests.createsNewOrderFromPaths")
unittest
{
    auto first = NamePath.path!(Person.getFirstName)();
    auto last = NamePath.path!(Person.getLastName)();
    assert(Order.desc("foo").withProperties(first, last) == Sort.by(Direction.DESC, "firstName", "lastName"));
}

@("SortUnitTests.translatesTypedSortCorrectly")
unittest
{
    auto nested = Sort.sort!Sample().by!(Sample.getNested)().by!(Person.getFirstName)();
    auto collection = Sort.sort!Sample().by!(Sample.getNesteds)().by!(Person.getFirstName)();
    auto map = Sort.sort!Sample().by!(Sample.getNames)().by!(Person.getFirstName)();

    assert(nested.iterator().next() == Order.by("nested.firstName"));
    assert(collection.iterator().next() == Order.by("nesteds.firstName"));
    assert(map.iterator().next() == Order.by("names.firstName"));
}

@("SortUnitTests.allowsCombiningTypedSorts")
unittest
{
    auto first = Sort.sort!Person().by!(Person.getFirstName)();
    auto last = Sort.sort!Person().by!(Person.getLastName)();

    assert(first.and(last) == Sort.by("firstName", "lastName"));
    assert(Sort.by("firstName").and(last) == Sort.by("firstName", "lastName"));
}

@("SortUnitTests.reversesTypedSortCorrectly")
unittest
{
    auto sorted = Sort.sort!Person().by!(Person.getFirstName)();
    assert(sorted.reverse() == Sort.by(Order.desc("firstName")));
    assert(sorted.descending() == Sort.by(Direction.DESC, "firstName"));
    assert(sorted.ascending() == Sort.by("firstName"));
}

@("Typed Sort rejects a member from the wrong type")
unittest
{
    static assert(!__traits(compiles, Sort.sort!Person().by!(Sample.getCount)()));
    static assert(!__traits(compiles, NamePath.path!(Person.getStaticName)()));
}

@("Typed properties keep JavaBeans acronyms and accept mixed property types")
unittest
{
    auto url = NamePath.path!(Person.getURL)();
    auto active = TypedPropertyPath!(Person, bool).path!(Person.isActive)();
    assert(Sort.by(url, active) == Sort.by("URL", "active"));
    assert(Sort.by(TypedPropertyPath!(Person, int).path!(Person.getÉtage)()) == Sort.by("étage"));
}
