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

// Behavioural tests for spring-ai v2.1.0's transformer/ContentFormatTransformer.java, which has no upstream test class.
// Modified by the Flint authors.
module content_format_transformer_tests;

import flint.ai.document : ContentFormatter, DefaultContentFormatter, Document, MetadataMode;
import flint.ai.transformer : ContentFormatTransformer;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : ArrayList, HashMap, List;
import std.exception : collectException;
import std.typecons : Nullable;

@safe:

private alias Text = Nullable!string;
private alias Metadata = HashMap!(string, Any);

private final class MarkerFormatter : ContentFormatter
{
    override string format(Document document, MetadataMode mode)
    {
        return "[" ~ document.getText().get() ~ "]";
    }
}

private Document textDocument(string id, string text)
{
    return new Document(id, Text(text), new Metadata());
}

private List!Document documentList(Document[] documents)
{
    auto list = new ArrayList!Document();
    foreach (document; documents)
        list.add(document);
    return list;
}

@("constructor rejects a null formatter")
unittest
{
    const error = collectException!IllegalArgumentException(new ContentFormatTransformer(null));
    assert(error !is null && error.msg == "ContentFormatter is required");
}

@("a non-default transformer replaces each document's formatter")
unittest
{
    auto first = textDocument("a", "one");
    auto second = textDocument("b", "two");
    auto marker = new MarkerFormatter();
    auto transformer = new ContentFormatTransformer(marker);
    auto result = transformer.apply(documentList([first, second]));

    assert(result.size() == 2 && result.get(0) is first && result.get(1) is second);
    assert(first.getContentFormatter() is marker && second.getContentFormatter() is marker);
    assert(first.getFormattedContent() == "[one]");
    assert(transformer.transform(documentList([textDocument("c", "three")])).get(0).getFormattedContent() == "[three]");
}

@("default formatters merge exclusions, metadata template and separator")
unittest
{
    auto source = DefaultContentFormatter.builder().withExcludedEmbedMetadataKeys("sourceEmbed")
        .withExcludedInferenceMetadataKeys("sourceInference")
        .withMetadataTemplate("{key}={value}").withMetadataSeparator(Text("; ")).withTextTemplate("{content}").build();
    auto update = DefaultContentFormatter.builder().withExcludedEmbedMetadataKeys("updateEmbed")
        .withExcludedInferenceMetadataKeys("updateInference")
        .withMetadataTemplate("{key}: {value}")
        .withMetadataSeparator(Text("|")).withTextTemplate("[{metadata_string}] {content}").build();

    auto document = textDocument("a", "body");
    document.setContentFormatter(source);
    new ContentFormatTransformer(update).apply(documentList([document]));

    auto merged = cast(DefaultContentFormatter) document.getContentFormatter();
    assert(merged !is null);
    assert(merged.getMetadataTemplate() == "{key}={value}");
    assert(merged.getMetadataSeparator() == "; ");
    assert(merged.getTextTemplate() == "{content}");
    assert(merged.getExcludedEmbedMetadataKeys().toArray() == ["sourceEmbed", "updateEmbed"]);
    assert(merged.getExcludedInferenceMetadataKeys().toArray() == [
        "sourceInference", "updateInference"
    ]);
}

@("disableTemplateRewrite keeps the document's text template")
unittest
{
    auto source = DefaultContentFormatter.builder().withTextTemplate("DOC:{content}").build();
    auto update = DefaultContentFormatter.builder().withTextTemplate("UPDATE:{content}").build();

    auto document = textDocument("a", "body");
    document.setContentFormatter(source);
    new ContentFormatTransformer(update, true).apply(documentList([document]));

    auto merged = cast(DefaultContentFormatter) document.getContentFormatter();
    // Java's disableTemplateRewrite skips copying the document template, so the builder's
    // own default text template survives.
    assert(merged !is null && merged.getTextTemplate() == "{metadata_string}\n\n{content}");
}

@("a document with the default formatter is merged, not replaced")
unittest
{
    auto document = new Document(Text("body"), new Metadata());
    const before = document.getContentFormatter();
    new ContentFormatTransformer(DefaultContentFormatter.builder().withMetadataTemplate("{key}={value}").build()).apply(
            documentList([document]));
    assert(document.getContentFormatter() !is before);
    assert(document.getContentFormatter().format(document, MetadataMode.ALL) == "\n\nbody");
}
