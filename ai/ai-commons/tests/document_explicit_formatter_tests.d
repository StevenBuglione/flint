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

// Ported from spring-ai v2.1.0, spring-ai-commons/src/test/java/org/springframework/ai/document/ContentFormatterTests.java
// Modified by the Flint authors.
module document_explicit_formatter_tests;

import flint.ai.document : ContentFormatter, Document, MetadataMode;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : HashMap;
import std.exception : collectException;
import std.typecons : Nullable;

@safe:

private alias Text = Nullable!string;

private final class ExplicitFormatter : ContentFormatter
{
    override string format(Document document, MetadataMode mode)
    {
        assert(mode == MetadataMode.EMBED);
        return "[" ~ document.getText().get() ~ "]";
    }
}

private void checkInvalid(lazy Document candidate, string message)
{
    const error = collectException!IllegalArgumentException(candidate);
    assert(error !is null && error.msg == message);
}

@("shouldThrowWhenIdIsNull")
unittest
{
    checkInvalid(new Document(null, Text("text"), new HashMap!(string, Any)()), "id cannot be null or empty");
}

@("shouldThrowWhenIdIsEmpty")
unittest
{
    checkInvalid(new Document("", Text("text"), new HashMap!(string, Any)()), "id cannot be null or empty");
}

@("shouldThrowWhenMetadataIsNull")
unittest
{
    checkInvalid(new Document("fixture", Text("Sample text"), null), "metadata cannot be null");
}

@("shouldThrowWhenMetadataHasNullKey")
unittest
{
    auto metadata = new HashMap!(string, Any)();
    metadata.put(null, Any.of("value"));
    checkInvalid(new Document("fixture", Text("Sample text"), metadata), "metadata cannot have null keys");
}

@("shouldThrowWhenMetadataHasNullValue")
unittest
{
    auto metadata = new HashMap!(string, Any)();
    metadata.put("key", Any.init);
    checkInvalid(new Document("fixture", Text("Sample text"), metadata), "metadata cannot have null values");
}

@("shouldThrowWhenFormatterIsNull")
unittest
{
    auto document = new Document("fixture", Text("Sample text"), new HashMap!(string, Any)());
    const error = collectException!IllegalArgumentException(document.getFormattedContent(null, MetadataMode.ALL));
    assert(error !is null && error.msg == "formatter must not be null");
}

@("explicit formatters receive the document and selected mode")
unittest
{
    auto document = new Document("fixture", Text("Sample text"), new HashMap!(string, Any)());
    ContentFormatter formatter = new ExplicitFormatter();
    assert(document.getFormattedContent(formatter, MetadataMode.EMBED) == "[Sample text]");
    const error = collectException!IllegalArgumentException(document.getFormattedContent(formatter,
            Nullable!MetadataMode.init));
    assert(error !is null && error.msg == "Metadata mode must not be null");
}

@("explicit text construction distinguishes empty and absent text and copies metadata")
unittest
{
    auto original = new HashMap!(string, Any)();
    original.put("key", Any.of("keep"));
    auto document = new Document("fixture", Text(""), original);
    assert(document.getId() == "fixture" && document.isText());
    assert(!document.getText().isNull && document.getText().get() == "");
    original.put("key", Any.of("changed"));
    assert(document.getMetadata().get("key").get!string == "keep");
    checkInvalid(new Document("fixture", Text.init, original), "exactly one of text or media must be specified");
}

@("document IDs distinguish Java whitespace from nonbreaking spaces")
unittest
{
    auto entries = new HashMap!(string, Any)();
    enum blank = "\t\n\v\f\r\x1c\x1d\x1e\x1f \u1680\u2000\u2006\u2008\u200a\u2028\u2029\u205f\u3000";
    checkInvalid(new Document(blank, Text("text"), entries), "id cannot be null or empty");
    foreach (string id; ["\u00a0", "\u0085", "\u2007", "\u202f", "文"])
        assert(new Document(id, Text("text"), entries).getId() == id);
}
