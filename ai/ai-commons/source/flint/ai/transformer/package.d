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

// Ported from spring-ai v2.1.0, spring-ai-commons/src/main/java/org/springframework/ai/transformer/ContentFormatTransformer.java
// Modified by the Flint authors.
module flint.ai.transformer;

import flint.ai.document : ContentFormatter, DefaultContentFormatter, Document, DocumentTransformer;
import flint.java.util : ArrayList, List;
import flint.util : Assert;
import std.typecons : Nullable;

@safe:

/// Applies a content formatter to every document in a list.
final class ContentFormatTransformer : DocumentTransformer
{
    private bool disableTemplateRewrite_;
    private ContentFormatter contentFormatter_;

    /// Creates a transformer that also rewrites each document's text template.
    this(ContentFormatter contentFormatter)
    {
        this(contentFormatter, false);
    }

    /// Creates a transformer, optionally leaving each document's text template untouched.
    this(ContentFormatter contentFormatter, bool disableTemplateRewrite)
    {
        Assert.notNull(contentFormatter, "ContentFormatter is required");
        contentFormatter_ = contentFormatter;
        disableTemplateRewrite_ = disableTemplateRewrite;
    }

    /// Formats every document in place and returns the same list.
    override List!Document apply(List!Document documents)
    {
        documents.forEach((Document document) { processDocument(document); });
        return documents;
    }

    mixin DocumentTransformer.Defaults;

    private void processDocument(Document document)
    {
        auto documentFormatter = cast(DefaultContentFormatter) document.getContentFormatter();
        auto updateFormatter = cast(DefaultContentFormatter) contentFormatter_;
        if (documentFormatter !is null && updateFormatter !is null)
            mergeFormatter(document, documentFormatter, updateFormatter);
        else
            document.setContentFormatter(contentFormatter_);
    }

    private void mergeFormatter(Document document, DefaultContentFormatter documentFormatter,
            DefaultContentFormatter updateFormatter)
    {
        List!string embedExcludeKeys = new ArrayList!string(documentFormatter.getExcludedEmbedMetadataKeys());
        embedExcludeKeys.addAll(updateFormatter.getExcludedEmbedMetadataKeys());

        List!string inferenceExcludeKeys = new ArrayList!string(documentFormatter.getExcludedInferenceMetadataKeys());
        inferenceExcludeKeys.addAll(updateFormatter.getExcludedInferenceMetadataKeys());

        auto builder = DefaultContentFormatter.builder().withExcludedEmbedMetadataKeys(embedExcludeKeys)
            .withExcludedInferenceMetadataKeys(inferenceExcludeKeys)
            .withMetadataTemplate(documentFormatter.getMetadataTemplate())
            .withMetadataSeparator(Nullable!string(documentFormatter.getMetadataSeparator()));

        if (!disableTemplateRewrite_)
            builder.withTextTemplate(documentFormatter.getTextTemplate());

        document.setContentFormatter(builder.build());
    }
}
