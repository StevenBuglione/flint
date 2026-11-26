/*
 * Copyright 2023-present the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Ported from spring-ai v2.1.0, spring-ai-model/src/test/java/org/springframework/ai/converter/ListOutputConverterTest.java
// Modified by the Flint authors.
module list_output_converter_test;

import flint.ai.converter : ListOutputConverter;
import flint.core.convert.support : DefaultConversionService;
import flint.java.lang : UnsupportedOperationException;
import flint.java.util : List;
import std.exception : assertThrown;

@safe:

private List!string convertCsv(string input)
{
    return new ListOutputConverter(new DefaultConversionService()).convert(input);
}

private void assertValues(string input, scope const(string)[] expected)
{
    auto values = convertCsv(input);
    assert(values !is null && values.size() == expected.length);
    foreach (i, value; expected)
    {
        const actual = values.get(cast(int) i);
        assert(actual !is null && actual == value);
    }
}

private void assertNonNullValues(string input, int count)
{
    auto values = convertCsv(input);
    assert(values !is null && values.size() == count);
    foreach (value; values.toArray())
        assert(value !is null);
}

private void assertNonEmptyValues(string input)
{
    auto values = convertCsv(input);
    assert(values !is null && !values.isEmpty());
    foreach (value; values.toArray())
        assert(value !is null);
}

@("csv")
unittest
{
    assertValues("foo, bar, baz", ["foo", "bar", "baz"]);
}

@("csvWithoutSpaces")
unittest
{
    assertValues("A,B,C", ["A", "B", "C"]);
}

@("csvWithExtraSpaces")
unittest
{
    assertValues("A  ,   B   ,  C  ", ["A", "B", "C"]);
}

@("csvWithSingleItem")
unittest
{
    assertValues("single-item", ["single-item"]);
}

@("csvWithEmptyString")
unittest
{
    assertValues("", []);
}

@("csvWithEmptyValues")
unittest
{
    assertValues("A, , C", ["A", "", "C"]);
}

@("csvWithOnlyCommas")
unittest
{
    assertValues(",,", ["", "", ""]);
}

@("csvWithTrailingComma")
unittest
{
    assertValues("A, B,", ["A", "B", ""]);
}

@("csvWithLeadingComma")
unittest
{
    assertValues(", A, B", ["", "A", "B"]);
}

@("csvWithSpecialCharacters")
unittest
{
    assertValues("value@example.com, item#123, $data%", ["value@example.com", "item#123", "$data%"]);
}

@("csvWithVariousInputs")
unittest
{
    foreach (input; ["a,b,c", "1,2,3", "X,Y,Z", "alpha,beta,gamma"])
        assertNonNullValues(input, 3);
}

@("csvWithTabsAndSpecialWhitespace")
unittest
{
    assertNonNullValues("A\t, \tB\r, \nC ", 3);
}

@("csvWithOnlySpacesAndCommas")
unittest
{
    assertValues(" , , ", ["", "", ""]);
}

@("csvWithBooleanLikeValues")
unittest
{
    assertValues("true, false, TRUE, FALSE, yes, no", [
        "true", "false", "TRUE", "FALSE", "yes", "no"
    ]);
}

@("csvWithDifferentDataTypes")
unittest
{
    assertValues("string, 123, 45.67, true, null", ["string", "123", "45.67", "true", "null"]);
}

@("csvWithAlternativeDelimiters")
unittest
{
    assertNonEmptyValues("A; B; C");
}

@("csvWithQuotedValues")
unittest
{
    assertNonNullValues(`"quoted value", normal, "another quoted"`, 3);
}

@("csvWithEscapedQuotes")
unittest
{
    assertNonEmptyValues(`"value with ""quotes""", normal, "escaped"`);
}

@("csvWithOnlyWhitespace")
unittest
{
    assertValues("   \t\n   ", [""]);
}

@("csvWithCommasInQuotedValues")
unittest
{
    assertNonEmptyValues(`"value, with, commas", normal, "another, comma"`);
}

@("csvWithNewlinesInQuotedValues")
unittest
{
    assertNonEmptyValues("\"line1\nline2\", normal, \"another\nline\"");
}

@("csvWithMixedQuotingStyles")
unittest
{
    assertNonNullValues("'single quoted', \"double quoted\", `backtick quoted`, unquoted", 4);
}

@("csvWithOnlyCommasAndSpaces")
unittest
{
    assertValues(" , , , ", ["", "", "", ""]);
}

@("csvWithMalformedQuoting")
unittest
{
    assertNonEmptyValues(`"unclosed quote, normal, "properly closed"`);
}

@("list output converter preserves null fallback and model format")
unittest
{
    auto converter = new ListOutputConverter();
    auto absent = converter.convert(null);
    assert(absent !is null && absent.isEmpty());
    assert(absent is new ListOutputConverter().convert(null));
    assertThrown!UnsupportedOperationException(absent.add("unexpected"));
    assert(converter.getJsonSchema() == "");
    enum instructions = "Respond with only a list of comma-separated values, without any leading or trailing text.\n";
    assert(converter.getFormat() == instructions ~ "Example format: foo, bar, baz\n");
}

@("list output converter delegates to the supplied conversion service")
unittest
{
    List!string expected = List!string.of("custom result");
    auto service = new DefaultConversionService();
    service.addConverter!(string, List!string)((string value) {
        assert(value == "custom");
        return expected;
    });
    auto converter = new ListOutputConverter(service);
    assert(converter.getConversionService() is service);
    assert(converter.convert("custom") is expected);
}
