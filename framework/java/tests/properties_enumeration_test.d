module properties_enumeration_test;

import flint.engine.aot.any : Any;
import flint.java.util : NoSuchElementException, Properties;
import flint.java.util.enumeration : Enumeration;
import std.exception : assertThrown;

@safe:

private string[] values(Enumeration!Any enumeration)
{
    string[] result;
    while (enumeration.hasMoreElements())
        result ~= enumeration.nextElement().get!string;
    return result;
}

@("Properties.keys and elements walk only this set, in insertion order, as a snapshot") unittest
{
    auto defaults = new Properties;
    defaults.setProperty("a", "A");
    defaults.setProperty("b", "B");
    auto properties = new Properties(defaults);
    properties.setProperty("b", "B2");
    properties.setProperty("c", "C");

    auto keys = properties.keys();
    auto elements = properties.elements();
    properties.setProperty("later", "seen-by-no-one");
    assert(keys.hasMoreElements());
    assert(keys.nextElement().get!string == "b");
    assert(keys.nextElement().get!string == "c");
    assert(!keys.hasMoreElements());
    assertThrown!NoSuchElementException(keys.nextElement());

    assert(values(elements) == ["B2", "C"]);
}

@("Properties.propertyNames walks the deduplicated union with the defaults first") unittest
{
    auto defaults = new Properties;
    defaults.setProperty("a", "A");
    defaults.setProperty("b", "B");
    auto properties = new Properties(defaults);
    properties.setProperty("b", "B2");
    properties.setProperty("c", "C");

    assert(values(properties.propertyNames()) == ["a", "b", "c"]);

    auto empty = new Properties;
    assert(!empty.propertyNames().hasMoreElements());
}

@("Properties enumerations convert to the canonical Iterator") unittest
{
    auto properties = new Properties;
    properties.setProperty("key", "value");
    auto iterator = properties.keys().asIterator();
    assert(iterator.hasNext());
    assert(iterator.next().get!string == "key");
    assert(!iterator.hasNext());
}
