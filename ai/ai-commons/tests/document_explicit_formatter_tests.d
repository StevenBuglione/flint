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

import flint.ai.document : ContentFormatter, DefaultContentFormatter, Document, MetadataMode;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException, UnsupportedOperationException;
import flint.java.util : ArrayList, HashMap, List;
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

@("metadataImmutability")
unittest
{
    // Supply the ID explicitly because this test exercises the metadata snapshot.
    auto original = new HashMap!(string, Any)();
    original.put("key", Any.of("value"));
    auto document = new Document("fixture", Text("test"), original);
    original.put("newKey", Any.of("newValue"));

    auto metadata = document.getMetadata();
    assert(metadata.size() == 1);
    assert(metadata.get("key").get!string() == "value");
    assert(!metadata.containsKey("newKey"));
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

@("standalone default configuration formats the pinned document")
unittest
{
    auto metadata = new HashMap!(string, Any)();
    metadata.put("llmKey2", Any.of("value4"));
    metadata.put("embedKey1", Any.of("value1"));
    metadata.put("embedKey2", Any.of("value2"));
    metadata.put("embedKey3", Any.of("value3"));
    auto document = new Document("fixture", Text("The World is Big and Salvation Lurks Around the Corner"), metadata);
    auto formatter = DefaultContentFormatter.defaultConfig();
    version (Windows)
        enum separator = "\r\n";
    else
        enum separator = "\n";
    enum expected = "llmKey2: value4" ~ separator ~ "embedKey1: value1" ~ separator ~ "embedKey2: value2"
        ~ separator ~ "embedKey3: value3\n\n" ~ "The World is Big and Salvation Lurks Around the Corner";
    assert(document.getFormattedContent(formatter, MetadataMode.ALL) == expected);
    assert(formatter.format(document, MetadataMode.ALL) == expected);
    assert(document.getFormattedContent(formatter, MetadataMode.EMBED) == expected);
    assert(document.getFormattedContent(formatter, MetadataMode.INFERENCE) == expected);
    assert(document.getFormattedContent(formatter,
            MetadataMode.NONE) == "\n\nThe World is Big and Salvation Lurks Around the Corner");
    assert(formatter !is DefaultContentFormatter.defaultConfig());
}

@("custom configuration applies exclusions only to their corresponding modes")
unittest
{
    auto metadata = new HashMap!(string, Any)();
    metadata.put("inference", Any.of("shown for inference"));
    metadata.put("embed", Any.of(4.0));
    auto document = new Document("fixture", Text("{metadata_string}"), metadata);
    auto formatter = DefaultContentFormatter.builder().withMetadataTemplate("{key}={value}")
        .withMetadataSeparator(Text(""))
        .withTextTemplate("[{metadata_string}]{content}/{content}")
        .withExcludedEmbedMetadataKeys("inference").withExcludedInferenceMetadataKeys("embed").build();
    assert(formatter.getMetadataTemplate() == "{key}={value}");
    assert(formatter.getMetadataSeparator() == "");
    assert(formatter.getTextTemplate() == "[{metadata_string}]{content}/{content}");
    assert(formatter.getExcludedEmbedMetadataKeys().get(0) == "inference");
    assert(formatter.getExcludedInferenceMetadataKeys().get(0) == "embed");
    assert(formatter.format(document,
            MetadataMode.ALL) == "[inference=shown for inferenceembed=4.0]{metadata_string}/{metadata_string}");
    assert(formatter.format(document,
            MetadataMode.INFERENCE) == "[inference=shown for inference]{metadata_string}/{metadata_string}");
    assert(formatter.format(document, MetadataMode.EMBED) == "[embed=4.0]{metadata_string}/{metadata_string}");
    assert(formatter.format(document, MetadataMode.NONE) == "[]{metadata_string}/{metadata_string}");
}

@("exclusion lists are live unmodifiable views and builder from preserves them")
unittest
{
    auto keys = new ArrayList!string();
    keys.add("first");
    auto formatter = DefaultContentFormatter.builder().withExcludedEmbedMetadataKeys(keys).build();
    auto copied = DefaultContentFormatter.builder().from(formatter).build();
    auto view = formatter.getExcludedEmbedMetadataKeys();
    keys.add("second");
    assert(view.size() == 2 && view.get(1) == "second");
    assert(copied.getExcludedEmbedMetadataKeys().get(1) == "second");
    assert(collectException!UnsupportedOperationException(view.add("third")) !is null);
}

@("formatter builder distinguishes missing and empty configuration")
unittest
{
    auto builder = DefaultContentFormatter.builder();
    assert(collectException!IllegalArgumentException(builder.withMetadataTemplate("\u3000")) !is null);
    assert(collectException!IllegalArgumentException(builder.withTextTemplate("")) !is null);
    assert(collectException!IllegalArgumentException(builder.withMetadataSeparator(Text.init)) !is null);
    assert(collectException!IllegalArgumentException(
            builder.withExcludedEmbedMetadataKeys(cast(List!string) null)) !is null);
    assert(collectException!IllegalArgumentException(
            builder.withExcludedInferenceMetadataKeys(cast(string[]) null)) !is null);
    auto formatter = builder.withExcludedEmbedMetadataKeys().withExcludedInferenceMetadataKeys().build();
    assert(formatter.getExcludedEmbedMetadataKeys().isEmpty());
    assert(formatter.getExcludedInferenceMetadataKeys().isEmpty());
}

@("a placeholder with absent output yields a present empty string")
unittest
{
    auto document = new Document("fixture", Text(""), new HashMap!(string, Any)());
    auto formatter = DefaultContentFormatter.builder().withTextTemplate("{metadata_string}{content}").build();
    const formatted = formatter.format(document, MetadataMode.NONE);
    assert(formatted !is null && formatted.length == 0);
}

@("equalDocuments")
unittest
{
    auto metadata = new HashMap!(string, Any)();
    metadata.put("key", Any.of("value"));
    auto first = new Document("id", Text("text"), metadata);
    auto second = new Document("id", Text("text"), metadata);
    assert(first == second);
    assert(first.hashCode() == second.hashCode());
}

@("differentIds")
unittest
{
    auto metadata = new HashMap!(string, Any)();
    metadata.put("key", Any.of("value"));
    auto first = new Document("id1", Text("text"), metadata);
    auto second = new Document("id2", Text("text"), metadata);
    assert(first != second);
}

@("differentText")
unittest
{
    auto metadata = new HashMap!(string, Any)();
    metadata.put("key", Any.of("value"));
    auto first = new Document("id", Text("text1"), metadata);
    auto second = new Document("id", Text("text2"), metadata);
    assert(first != second);
}

private final class TestDocument : Document
{
    this(string id)
    {
        super(id, Text(""), new HashMap!(string, Any)());
    }
}

@("document equality requires the same runtime class")
unittest
{
    auto base = new Document("id", Text(""), new HashMap!(string, Any)());
    auto derived = new TestDocument("id");
    auto peer = new TestDocument("id");
    assert(base.equals(base));
    assert(!base.equals(derived) && !derived.equals(base));
    assert(derived.equals(peer));
    assert(!base.equals(null) && !base.equals(new Object()));
}

@("document equality and hash follow the live metadata map")
unittest
{
    auto firstMetadata = new HashMap!(string, Any)();
    firstMetadata.put("a", Any.of("one"));
    firstMetadata.put("b", Any.of("two"));
    auto secondMetadata = new HashMap!(string, Any)();
    secondMetadata.put("b", Any.of("two"));
    secondMetadata.put("a", Any.of("one"));
    auto first = new Document("id", Text("text"), firstMetadata);
    auto second = new Document("id", Text("text"), secondMetadata);
    assert(first.equals(second));
    assert(first.hashCode() == second.hashCode());
    second.getMetadata().put("a", Any.of("changed"));
    assert(!first.equals(second));
}

@("document hash includes the absent media and score fields")
unittest
{
    auto document = new Document("a", Text("b"), new HashMap!(string, Any)());
    // Java 21 Objects.hash("a", "b", null, Map.of(), null).
    assert(document.hashCode() == 121_130_206);
}

@("explicit text documents display null media and score")
unittest
{
    auto metadata = new HashMap!(string, Any)();
    auto document = new Document("a", Text("b"), metadata);
    assert(document.toString() == "Document{id='a', text='b', media='null', metadata={}, score=null}");
    metadata.put("key", Any.of("value"));
    document = new Document("customId", Text("Test content"), metadata);
    enum expected = "Document{id='customId', text='Test content', media='null', metadata={key=value}, score=null}";
    assert(document.toString() == expected);
}
