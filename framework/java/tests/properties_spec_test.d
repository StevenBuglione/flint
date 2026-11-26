module properties_spec_test;

import flint.java.lang : NullPointerException, UnsupportedOperationException;
import flint.java.util : Properties;
import std.exception : assertThrown;

@safe:

@("Properties sees live defaults and preserves explicit empty values") unittest
{
    auto defaults = new Properties;
    auto properties = new Properties(defaults);
    assert(properties.getProperty("title") is null);
    defaults.setProperty("title", "home");
    assert(properties.getProperty("title") == "home");
    assert(properties.setProperty("title", "away") is null);
    assert(properties.setProperty("title", "next") == "away");
    assert(properties.getProperty("absent", "fallback") == "fallback");

    properties.load("title=\n");
    assert(properties.getProperty("title", "fallback") == "");
    assert(properties.getProperty("title") !is null);
}

@("Properties names are an unmodifiable snapshot of own and default keys") unittest
{
    auto defaults = new Properties;
    defaults.setProperty("remote", "true");
    auto properties = new Properties(defaults);
    properties.setProperty("local", "true");
    auto names = properties.stringPropertyNames();
    assert(names.size() == 2 && names.contains("remote") && names.contains("local"));
    assertThrown!UnsupportedOperationException(names.add("new"));
    assertThrown!UnsupportedOperationException(names.remove("local"));
    properties.setProperty("later", "true");
    defaults.setProperty("fallback", "true");
    assert(names.size() == 2);
    assert(properties.stringPropertyNames().size() == 4);
}

@("Properties rejects null keys and values at its string accessors") unittest
{
    auto properties = new Properties;
    assertThrown!NullPointerException(properties.getProperty(null));
    assertThrown!NullPointerException(properties.getProperty(null, "fallback"));
    assertThrown!NullPointerException(properties.setProperty(null, "text"));
    assertThrown!NullPointerException(properties.setProperty("key", null));
    assert(properties.isEmpty());
    properties.setProperty("", "");
    assert(properties.getProperty("", "fallback") == "");
}
