// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/context/properties/source/MutuallyExclusiveConfigurationPropertiesExceptionTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors.
module mutually_exclusive_configuration_properties_test;

import flint.boot.context.properties.source : MutuallyExclusiveConfigurationPropertiesException;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException, NullPointerException;
import flint.java.util : Collection, List, Map;
import flint.java.util.function_ : Consumer;
import std.exception : assertThrown;

@safe:

private alias Conflict = MutuallyExclusiveConfigurationPropertiesException;
private alias Names = List!string;
private alias Properties = Map!(string, Any);
private alias PropertyAction = void delegate(Properties) @safe;
private enum configuredError = "'configuredNames' must contain 2 or more names";
private enum exclusiveError = "'mutuallyExclusiveNames' must contain 2 or more names";

private void assertInvalid(Collection!string configured, Collection!string exclusive, string message)
{
    try
        new Conflict(configured, exclusive);
    catch (IllegalArgumentException error)
    {
        assert(error.msg == message);
        return;
    }
    assert(0, "invalid name lists must throw");
}

@("createWhenConfiguredNamesIsNullThrowsException")
unittest
{
    assertInvalid(null, Names.of("a", "b"), configuredError);
}

@("createWhenConfiguredNamesContainsOneElementThrowsException")
unittest
{
    assertInvalid(Names.of("a"), Names.of("a", "b"), configuredError);
}

@("createWhenMutuallyExclusiveNamesIsNullThrowsException")
unittest
{
    assertInvalid(Names.of("a", "b"), null, exclusiveError);
}

@("createWhenMutuallyExclusiveNamesContainsOneElementThrowsException")
unittest
{
    assertInvalid(Names.of("a", "b"), Names.of("a"), exclusiveError);
}

@("createBuildsSensibleMessage")
unittest
{
    auto names = Names.of("a", "b");
    enum expected = "The configuration properties 'a, b' are mutually exclusive "
        ~ "and 'a, b' have been configured together";
    assert((new Conflict(names, names)).msg == expected);
}

@("getConfiguredNamesReturnsConfiguredNames")
unittest
{
    auto exception = new Conflict(Names.of("a", "b"), Names.of("a", "b", "c"));
    assert(exception.getConfiguredNames().toArray() == ["a", "b"]);
}

@("getMutuallyExclusiveNamesReturnsMutuallyExclusiveNames")
unittest
{
    auto exception = new Conflict(Names.of("a", "b"), Names.of("a", "b", "c"));
    assert(exception.getMutuallyExclusiveNames().toArray() == ["a", "b", "c"]);
}

@("throwIfMultipleNonNullValuesInWhenEntriesHasAllNullsDoesNotThrowException")
unittest
{
    Conflict.throwIfMultipleNonNullValuesIn((Properties entries) {
        entries.put("a", Any.init);
        entries.put("b", Any.init);
        entries.put("c", Any.init);
    });
}

@("throwIfMultipleNonNullValuesInWhenEntriesHasSingleNonNullDoesNotThrowException")
unittest
{
    Conflict.throwIfMultipleNonNullValuesIn((Properties entries) {
        entries.put("a", Any.init);
        entries.put("b", Any.of("B"));
        entries.put("c", Any.init);
    });
}

@("throwIfMultipleNonNullValuesInWhenEntriesHasTwoNonNullsThrowsException")
unittest
{
    try
        Conflict.throwIfMultipleNonNullValuesIn((Properties entries) {
            entries.put("a", Any.of("a"));
            entries.put("b", Any.of("B"));
            entries.put("c", Any.init);
        });
    catch (Conflict exception)
    {
        assert(exception.getConfiguredNames().toArray() == ["a", "b"]);
        assert(exception.getMutuallyExclusiveNames().toArray() == ["a", "b", "c"]);
        return;
    }
    assert(0, "two configured properties must conflict");
}

@("the Consumer overload counts false as a configured property")
unittest
{
    static final class AccessProperties : Consumer!Properties
    {
        override void accept(Properties entries)
        {
            entries.put("management.endpoint.info.access", Any.of("read-only"));
            entries.put("management.endpoint.info.enabled", Any.of(false));
        }
    }

    try
        Conflict.throwIfMultipleNonNullValuesIn(new AccessProperties);
    catch (Conflict exception)
    {
        assert(exception.getConfiguredNames().size() == 2);
        return;
    }
    assert(0, "an explicitly false property is configured");
}

@("the non-null value check rejects null consumers and delegates")
unittest
{
    assertThrown!NullPointerException(Conflict.throwIfMultipleNonNullValuesIn(null));
    assertThrown!NullPointerException(Conflict.throwIfMultipleNonNullValuesIn(cast(Consumer!Properties) null));
    assertThrown!NullPointerException(Conflict.throwIfMultipleNonNullValuesIn(cast(PropertyAction) null));
}
