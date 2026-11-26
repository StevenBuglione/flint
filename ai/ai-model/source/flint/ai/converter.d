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

// Ported from spring-ai v2.1.0, spring-ai-model/src/main/java/org/springframework/ai/converter/{FormatProvider,MarkdownCodeBlockCleaner,ResponseTextCleaner,StructuredOutputConverter,WhitespaceCleaner}.java
// Modified by the Flint authors.
module flint.ai.converter;

import flint.core.convert.converter : Converter;
import std.typecons : Nullable;

@safe:

private alias Text = Nullable!string;

/// Supplies formatting instructions for a model response.
interface FormatProvider
{
    /// Returns instructions describing the desired response format.
    string getFormat();
}

/// Converts a model's text response to a typed value.
interface StructuredOutputConverter(T) : Converter!(string, T), FormatProvider
{
    /// The schema value when no JSON schema is available.
    enum string NO_JSON_SCHEMA = "";

    /// Returns the converter's JSON schema.
    string getJsonSchema();

    /// Supplies the default schema for implementations that only provide formatting instructions (R3).
    mixin template Defaults()
    {
        override string getJsonSchema()
        {
            return "";
        }
    }
}

/// Cleans text returned by a model before a converter parses it.
interface ResponseTextCleaner
{
    /// Removes formatting while preserving absent input (R5).
    Text clean(Text text);
}

/// Trims leading and trailing characters removed by Java's String.trim.
class WhitespaceCleaner : ResponseTextCleaner
{
    /// Returns the trimmed text, or an absent value if the input was absent.
    override Text clean(Text text) pure nothrow @nogc
    {
        return text.isNull ? text : Text(trimJava(text.get()));
    }
}

/// Removes enclosing triple-backtick fences and trims their content.
class MarkdownCodeBlockCleaner : ResponseTextCleaner
{
    /// Cleans a fenced or plain model response.
    override Text clean(Text text) pure nothrow @nogc
    {
        if (text.isNull || text.get().length == 0)
            return text;

        string value = trimJava(text.get());
        enum fence = "```";
        enum width = fence.length;
        if (value.length <= 2 * width || value[0 .. width] != fence || value[$ - width .. $] != fence)
            return Text(value);

        auto content = value[width .. $ - width];
        foreach (i, char byte_; content)
        {
            if (byte_ == '\n')
            {
                content = content[i + 1 .. $];
                break;
            }
        }
        return Text(trimJava(content));
    }
}

private string trimJava(string text) pure nothrow @nogc
{
    while (text.length && text[0] <= ' ')
        text = text[1 .. $];
    while (text.length && text[$ - 1] <= ' ')
        text = text[0 .. $ - 1];
    return text;
}
