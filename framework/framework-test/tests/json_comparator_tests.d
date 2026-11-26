/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/test/json/JsonComparatorTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors. The shared cases exercise Flint's built-in comparator.
+/
module json_comparator_tests;

import flint.java.lang : IllegalStateException;
import flint.test.json : JsonComparator, JsonCompareMode, JsonComparison;
import std.typecons : Nullable;

@safe:

private alias JsonText = Nullable!string;
private alias Result = JsonComparison.Result;
private alias strict = JsonCompareMode.STRICT;
private alias lenient = JsonCompareMode.LENIENT;

private void assertMatch(JsonCompareMode mode, string expected, string actual)
{
    auto comparison = JsonComparator.of(mode).compare(JsonText(expected), JsonText(actual));
    assert(comparison.getResult() == Result.MATCH);
    assert(comparison.getMessage().isNull);
}

private void assertMismatch(JsonCompareMode mode, string expected, string actual)
{
    auto comparison = JsonComparator.of(mode).compare(JsonText(expected), JsonText(actual));
    assert(comparison.getResult() == Result.MISMATCH);
    assert(!comparison.getMessage().isNull && comparison.getMessage().get().length != 0);
}

@("strictWhenSameContentWithDifferentFormatting")
unittest
{
    assertMatch(strict, `{"a":1,"b":[1,2]}`, `{ "b" : [1, 2], "a" : 1 }`);
}

@("strictWhenExtraField")
unittest
{
    assertMismatch(strict, `{"a":1}`, `{"a":1,"b":2}`);
}

@("strictWhenDifferentArrayOrder")
unittest
{
    assertMismatch(strict, `{"a":[1,2]}`, `{"a":[2,1]}`);
}

@("strictWhenDifferentValue")
unittest
{
    assertMismatch(strict, `{"a":1}`, `{"a":2}`);
}

@("lenientWhenExtraField")
unittest
{
    assertMatch(lenient, `{"a":1}`, `{"a":1,"b":2}`);
}

@("lenientWhenDifferentArrayOrder")
unittest
{
    assertMatch(lenient, `{"a":[1,2]}`, `{"a":[2,1]}`);
}

@("lenientWhenExtraArrayItem")
unittest
{
    assertMismatch(lenient, `{"a":[1,2]}`, `{"a":[1,2,3]}`);
}

@("lenientWhenMissingField")
unittest
{
    assertMismatch(lenient, `{"a":1,"b":2}`, `{"a":1}`);
}

@("lenientWhenDifferentValue")
unittest
{
    assertMismatch(lenient, `{"a":1}`, `{"a":2}`);
}

@("whenBothNull")
unittest
{
    auto comparison = JsonComparator.of(strict).compare(JsonText.init, JsonText.init);
    assert(comparison.getResult() == Result.MATCH);
    assert(comparison.getMessage().isNull);
}

@("whenActualNull")
unittest
{
    auto comparison = JsonComparator.of(strict).compare(JsonText("{}"), JsonText.init);
    assert(comparison.getResult() == Result.MISMATCH);
    assert(comparison.getMessage().get() == "Expected null JSON");
}

@("whenExpectedNull")
unittest
{
    auto comparison = JsonComparator.of(strict).compare(JsonText.init, JsonText("{}"));
    assert(comparison.getResult() == Result.MISMATCH);
    assert(comparison.getMessage().get() == "Expected non-null JSON");
}

@("Lenient JSON comparison matches nested object subsets and preserves multiplicity")
unittest
{
    assertMatch(lenient, `[{"a":1},{"a":1,"b":2}]`, `[{"a":1,"b":2},{"a":1,"b":3}]`);
    assertMatch(lenient, `[[1,2],[3,4]]`, `[[4,3],[2,1]]`);
    assertMismatch(lenient, `[1,1,2]`, `[1,2,2]`);
    assertMismatch(lenient, `[{"a":null}]`, `[{}]`);
    assertMatch(strict, `{"n":1}`, `{"n":1.0}`);
}

@("Absent JSON and invalid JSON are distinct from a JSON null literal")
unittest
{
    assertMatch(strict, `null`, `null`);
    auto comparator = JsonComparator.of(strict);
    assert(comparator.compare(JsonText.init, JsonText("null")).getResult() == Result.MISMATCH);
    foreach (invalid; ["", "{", "{} []"])
    {
        try
        {
            comparator.compare(JsonText("{}"), JsonText(invalid));
            assert(false);
        }
        catch (IllegalStateException)
        {
        }
    }
}
