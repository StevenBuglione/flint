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

// Ported from spring-ai v2.1.0, spring-ai-commons/src/test/java/org/springframework/ai/observation/ObservabilityHelperTests.java
// Modified by the Flint authors.
module observability_helper_tests;

import flint.ai.observation : ObservabilityHelper;
import flint.engine.aot.any : Any;
import flint.java.lang : NullPointerException;
import flint.java.util : ArrayList, LinkedHashMap, List;
import std.exception : assertThrown;

@safe:

private alias Entries = LinkedHashMap!(string, Any);

@("shouldGetEmptyBracketsForEmptyMap")
unittest
{
    assert(ObservabilityHelper.concatenateEntries(new Entries()) == "[]");
}

@("shouldGetEntriesForNonEmptyMap")
unittest
{
    auto entries = new Entries();
    entries.put("a", Any.of("1"));
    entries.put("b", Any.of("2"));
    assert(ObservabilityHelper.concatenateEntries(entries) == `["a":"1", "b":"2"]`);
}

@("shouldGetEmptyBracketsForEmptyList")
unittest
{
    assert(ObservabilityHelper.concatenateStrings(List!string.of()) == "[]");
}

@("shouldGetEntriesForNonEmptyList")
unittest
{
    assert(ObservabilityHelper.concatenateStrings(List!string.of("a", "b")) == `["a", "b"]`);
}

@("shouldHandleSingleEntryMap")
unittest
{
    auto entries = new Entries();
    entries.put("key", Any.of("value"));
    assert(ObservabilityHelper.concatenateEntries(entries) == `["key":"value"]`);
}

@("shouldHandleSingleEntryList")
unittest
{
    assert(ObservabilityHelper.concatenateStrings(List!string.of("single")) == `["single"]`);
}

@("shouldHandleEmptyStringsInList")
unittest
{
    assert(ObservabilityHelper.concatenateStrings(List!string.of("", "non-empty", "")) == `["", "non-empty", ""]`);
}

@("shouldHandleNullInputsGracefully")
unittest
{
    assertThrown!NullPointerException(ObservabilityHelper.concatenateEntries(null));
    assertThrown!NullPointerException(ObservabilityHelper.concatenateStrings(null));
}

@("shouldHandleNullValuesInMap")
unittest
{
    auto entries = new Entries();
    entries.put("key1", Any.of("value1"));
    entries.put("key2", Any.init);
    entries.put("key3", Any.of("value3"));
    assert(ObservabilityHelper.concatenateEntries(entries) == `["key1":"value1", "key2":"null", "key3":"value3"]`);
}

@("shouldHandleNullValuesInList")
unittest
{
    const values = ["first", null, "third"];
    assert(ObservabilityHelper.concatenateStrings(new ArrayList!string(values.dup)) == `["first", "null", "third"]`);
}

@("shouldHandleSpecialCharactersInMapValues")
unittest
{
    auto entries = new Entries();
    entries.put("quotes", Any.of(`value with "quotes"`));
    entries.put("newlines", Any.of("value\nwith\nnewlines"));
    entries.put("tabs", Any.of("value\twith\ttabs"));
    entries.put("backslashes", Any.of(`value\with\backslashes`));
    assert(ObservabilityHelper.concatenateEntries(
            entries) == "[\"quotes\":\"value with \"quotes\"\", \"newlines\":\"value\nwith\nnewlines\", "
            ~ "\"tabs\":\"value\twith\ttabs\", \"backslashes\":\"value\\with\\backslashes\"]");
}

@("shouldHandleSpecialCharactersInList")
unittest
{
    const values = [
        `string with "quotes"`, "string\nwith\nnewlines", "string\twith\ttabs",
        `string\with\backslashes`
    ];
    const result = ObservabilityHelper.concatenateStrings(new ArrayList!string(values.dup));
    assert(result == "[\"string with \"quotes\"\", \"string\nwith\nnewlines\", "
            ~ "\"string\twith\ttabs\", \"string\\with\\backslashes\"]");
}

@("shouldHandleWhitespaceOnlyStrings")
unittest
{
    assert(ObservabilityHelper.concatenateStrings(List!string.of("   ", "\t", "\n",
            " \t\n ")) == "[\"   \", \"\t\", \"\n\", \" \t\n \"]");
}

@("shouldHandleNumericAndBooleanValues")
unittest
{
    auto entries = new Entries();
    entries.put("integer", Any.of(1));
    entries.put("double", Any.of(1.1));
    entries.put("boolean", Any.of(true));
    entries.put("string", Any.of("text"));
    assert(ObservabilityHelper.concatenateEntries(
            entries) == `["integer":"1", "double":"1.1", "boolean":"true", "string":"text"]`);
}

@("shouldHandleComplexObjectsAsValues")
unittest
{
    import std.string : indexOf;

    auto entries = new Entries();
    entries.put("list", Any.of(List!string.of("a", "b")));
    entries.put("array", Any.of(["x", "y"]));
    entries.put("object", Any.of(new Object()));
    const result = ObservabilityHelper.concatenateEntries(entries);
    assert(result.indexOf(`"list":"[a, b]"`) >= 0);
    assert(result.indexOf(`"array":`) >= 0);
    assert(result.indexOf(`"object":`) >= 0);
}

@("shouldProduceConsistentOutput")
unittest
{
    auto entries = new Entries();
    entries.put("key", Any.of("value"));
    auto values = List!string.of("item");
    assert(ObservabilityHelper.concatenateEntries(entries) == ObservabilityHelper.concatenateEntries(entries));
    assert(ObservabilityHelper.concatenateStrings(values) == ObservabilityHelper.concatenateStrings(values));
}

@("shouldHandleMapWithEmptyStringKeys")
unittest
{
    auto entries = new Entries();
    entries.put("", Any.of("empty key value"));
    entries.put("normal", Any.of("normal value"));
    assert(ObservabilityHelper.concatenateEntries(entries) == `["":"empty key value", "normal":"normal value"]`);
}

@("shouldFormatBracketsCorrectly")
unittest
{
    auto entries = new Entries();
    assert(ObservabilityHelper.concatenateEntries(entries) == "[]");
    assert(ObservabilityHelper.concatenateStrings(List!string.of()) == "[]");
    entries.put("a", Any.of("b"));
    assert(ObservabilityHelper.concatenateEntries(entries) == `["a":"b"]`);
    assert(ObservabilityHelper.concatenateStrings(List!string.of("item")) == `["item"]`);
}

private class NamedValue
{
    override string toString() const
    {
        return "named";
    }
}

@("uses the supplied map order and Java floating point and reference text")
unittest
{
    auto entries = new Entries();
    entries.put("z", Any.of(1.0));
    entries.put("a", Any.of(1.1f));
    entries.put("m", Any.of(new NamedValue()));
    assert(ObservabilityHelper.concatenateEntries(entries) == `["z":"1.0", "a":"1.1", "m":"named"]`);
}
