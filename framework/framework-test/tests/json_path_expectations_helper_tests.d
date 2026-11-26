/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/test/util/JsonPathExpectationsHelperTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors. The fixture uses standard JSON quoting.
+/
module json_path_expectations_helper_tests;

import flint.java.lang : AssertionError, IllegalArgumentException;
import flint.test.util : JsonPathExpectationsHelper;

@safe:

private alias Path = JsonPathExpectationsHelper;
private enum content = `{"str":"foo","num":5,"bool":true,"arr":[42],"colorMap":{"red":"rojo"},`
    ~ `"whitespace":"    ","emptyString":"","emptyArray":[],"emptyMap":{},"nullValue":null}`;

private void fails(scope void delegate() @safe check, string message)
{
    try
    {
        check();
        assert(false);
    }
    catch (AssertionError failure)
        assert(failure.getMessage() == message, failure.getMessage());
}

@("exists")
unittest
{
    foreach (expression; ["$.str", "$.emptyArray", "$.emptyMap"])
        Path(expression).exists(content);
}

@("doesNotExist")
unittest
{
    Path("$.bogus").doesNotExist(content);
}

@("valueIsEmpty")
unittest
{
    foreach (expression; ["$.emptyString", "$.emptyArray", "$.emptyMap"])
        Path(expression).assertValueIsEmpty(content);
}

@("valueIsNotEmpty")
unittest
{
    foreach (expression; ["$.str", "$.num", "$.bool", "$.arr", "$.colorMap"])
        Path(expression).assertValueIsNotEmpty(content);
}

@("hasJsonPath")
unittest
{
    Path("$.abc").hasJsonPath(`{"abc":"123"}`);
}

@("hasJsonPathWithNull")
unittest
{
    Path("$.abc").hasJsonPath(`{"abc":null}`);
}

@("doesNotHaveJsonPath")
unittest
{
    Path("$.abc").doesNotHaveJsonPath(`{}`);
}

@("doesNotHaveJsonPathWithNull")
unittest
{
    fails(() => Path("$.abc").doesNotHaveJsonPath(`{"abc":null}`),
            `Expected no value at JSON path "$.abc" but found: null`);
}

@("assertValue")
unittest
{
    Path("$.num").assertValue(content, 5);
}

@("assertNullValue")
unittest
{
    Path("$.nullValue").assertValue(content, null);
}

@("assertValueWithNumberConversion")
unittest
{
    Path("$.num").assertValue(content, 5.0);
}

@("JsonPath preserves field order and supports bracket names, negative indices and recursive descent")
unittest
{
    enum document = `{"items":[{"name":"first"},{"name":"last"}],"a.b":7,"ordered":{"z":9,"a":1}}`;
    Path("$.items[-1].name").assertValue(document, "last");
    Path("$['a.b']").assertValue(document, 7);
    Path("$..name").assertValue(document, ["first", "last"]);
    Path("$.ordered.*").assertValue(document, [9, 1]);
    auto values = Path("$..name").evaluateJsonPath(document);
    assert(values.isArray() && values.size() == 2);
}

@("JsonPath treats unwitnessed wildcard results as an empty selection")
unittest
{
    auto path = Path("$.emptyArray[*]");
    path.assertValueIsEmpty(content);
    path.doesNotExist(content);
    path.doesNotHaveJsonPath(content);
    fails(() => path.exists(content), `No value at JSON path "$.emptyArray[*]"`);
    fails(() => path.hasJsonPath(content), `No values for JSON path "$.emptyArray[*]"`);
}

@("Quoted JsonPath members treat brackets as part of the name and decode escapes")
unittest
{
    enum document = `{"a]b":{"value":7},"a'b":8,"a\"b":9,"a\\b":10,"a\nb":11,"🐈":12,"":13}`;
    Path(`$['a]b'].value`).assertValue(document, 7);
    Path(`$["a]b"]['value']`).assertValue(document, 7);
    Path(`$['a\'b']`).assertValue(document, 8);
    Path(`$["a\"b"]`).assertValue(document, 9);
    Path(`$['a"b\'c']`).assertValue(`{"a\"b'c":14}`, 14);
    Path(`$['a\\b']`).assertValue(document, 10);
    Path(`$['a\nb']`).assertValue(document, 11);
    Path(`$['\uD83D\uDC08']`).assertValue(document, 12);
    Path(`$['']`).assertValue(document, 13);
}

@("JsonPath rejects an unfinished quoted member or an invalid escape at construction")
unittest
{
    import std.exception : assertThrown;

    foreach (invalid; [`$['a]`, `$['a'`, `$['a'junk]`, `$['a\q']`])
        assertThrown!IllegalArgumentException(Path(invalid));
}

@("assertValueIsString")
unittest
{
    Path("$.str").assertValueIsString(content);
}

@("assertValueIsStringForAnEmptyString")
unittest
{
    Path("$.emptyString").assertValueIsString(content);
}

@("assertValueIsStringForNonString")
unittest
{
    fails(() => Path("$.bool").assertValueIsString(content), `Expected a string at JSON path "$.bool" but found: true`);
}

@("assertValueIsNumber")
unittest
{
    Path("$.num").assertValueIsNumber(content);
}

@("assertValueIsNumberForNonNumber")
unittest
{
    fails(() => Path("$.bool").assertValueIsNumber(content), `Expected a number at JSON path "$.bool" but found: true`);
}

@("assertValueIsBoolean")
unittest
{
    Path("$.bool").assertValueIsBoolean(content);
}

@("assertValueIsBooleanForNonBoolean")
unittest
{
    fails(() => Path("$.num").assertValueIsBoolean(content), `Expected a boolean at JSON path "$.num" but found: 5`);
}

@("assertValueIsArray")
unittest
{
    Path("$.arr").assertValueIsArray(content);
}

@("assertValueIsArrayForAnEmptyArray")
unittest
{
    Path("$.emptyArray").assertValueIsArray(content);
}

@("assertValueIsArrayForNonArray")
unittest
{
    fails(() => Path("$.str").assertValueIsArray(content), `Expected an array at JSON path "$.str" but found: 'foo'`);
}

@("assertValueIsMap")
unittest
{
    Path("$.colorMap").assertValueIsMap(content);
}

@("assertValueIsMapForAnEmptyMap")
unittest
{
    Path("$.emptyMap").assertValueIsMap(content);
}

@("assertValueIsMapForNonMap")
unittest
{
    fails(() => Path("$.str").assertValueIsMap(content), `Expected a map at JSON path "$.str" but found: 'foo'`);
}

@("assertValueIsEmptyForWhitespace")
unittest
{
    fails(() => Path("$.whitespace").assertValueIsEmpty(content),
            `Expected an empty value at JSON path "$.whitespace" but found: '    '`);
}

@("assertValueIsNotEmptyForAnEmptyString")
unittest
{
    fails(() => Path("$.emptyString").assertValueIsNotEmpty(content),
            `Expected a non-empty value at JSON path "$.emptyString" but found: ''`);
}

@("assertValueIsNotEmptyForAnEmptyArray")
unittest
{
    fails(() => Path("$.emptyArray").assertValueIsNotEmpty(content),
            `Expected a non-empty value at JSON path "$.emptyArray" but found: []`);
}

@("assertValueIsNotEmptyForAnEmptyMap")
unittest
{
    fails(() => Path("$.emptyMap").assertValueIsNotEmpty(content),
            `Expected a non-empty value at JSON path "$.emptyMap" but found: {}`);
}

@("doesNotExistForAnEmptyArray")
unittest
{
    fails(() => Path("$.emptyArray").doesNotExist(content),
            `Expected no value at JSON path "$.emptyArray" but found: []`);
}

@("doesNotExistForAnEmptyMap")
unittest
{
    fails(() => Path("$.emptyMap").doesNotExist(content), `Expected no value at JSON path "$.emptyMap" but found: {}`);
}
