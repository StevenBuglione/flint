module properties_list_test;

import flint.java.io : PrintWriter, StringWriter;
import flint.java.lang : NullPointerException;
import flint.java.util : Properties;
import std.exception : assertThrown;
import std.string : indexOf;

@safe:

@("Properties list writes the header and every own entry in insertion order, without the defaults") unittest
{
    auto defaults = new Properties;
    defaults.setProperty("inherited", "D");

    auto properties = new Properties(defaults);
    properties.setProperty("second", "2");
    properties.setProperty("first", "1");

    auto writer = new StringWriter();
    properties.list(new PrintWriter(writer));

    assert(writer.toString() == "-- listing properties --\n" ~ "second=2\n" ~ "first=1\n");
}

@("Properties list writes keys and values raw, not escaped as store does") unittest
{
    auto properties = new Properties;
    properties.setProperty("k k", "v=v\nx\\y");

    auto writer = new StringWriter();
    properties.list(new PrintWriter(writer));

    assert(writer.toString() == "-- listing properties --\n" ~ "k k=v=v\nx\\y\n");
}

@("Properties list leaves values of at most 40 UTF-16 units whole and cuts longer ones to 37 plus ...") unittest
{
    auto properties = new Properties;
    const forty = "0123456789012345678901234567890123456789";
    properties.setProperty("whole", forty);
    properties.setProperty("long", forty ~ "0");

    auto writer = new StringWriter();
    properties.list(new PrintWriter(writer));

    assert(writer.toString() == "-- listing properties --\n" ~ "whole=" ~ forty ~ "\n"
            ~ "long=0123456789012345678901234567890123456...\n");
}

@("Properties list replaces a surrogate split at the 37-unit cut with U+FFFD") unittest
{
    auto properties = new Properties;
    // 36 ASCII units, then an emoji's two UTF-16 units, then three more: 41 units, so the cut is inside the emoji.
    properties.setProperty("k", "012345678901234567890123456789012345" ~ "\U0001f600" ~ "XYZ");

    auto writer = new StringWriter();
    properties.list(new PrintWriter(writer));

    assert(writer.toString() == "-- listing properties --\n" ~ "k=012345678901234567890123456789012345\uFFFD...\n");
}

@("Properties list rejects a null writer") unittest
{
    auto properties = new Properties;
    assertThrown!NullPointerException(properties.list(null));
}
