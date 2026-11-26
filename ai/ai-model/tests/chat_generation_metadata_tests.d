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

// Ported from spring-ai v2.1.0, spring-ai-model/src/test/java/org/springframework/ai/chat/metadata/ChatGenerationMetadataTests.java
// Modified by the Flint authors.
module chat_generation_metadata_tests;

import flint.ai.chat.metadata : ChatGenerationMetadata, FinishReasonCategory;
import flint.ai.model : ResultMetadata;
import std.typecons : Nullable, nullable;

@safe:

@("thirdPartyImplementationKeepsRawReasonAndUsesDefaultCategory")
unittest
{
    ChatGenerationMetadata absent = new FixedFinishReasonMetadata(Nullable!string.init);
    const ResultMetadata result = absent;
    assert(cast(const ChatGenerationMetadata) result is absent);
    assert(absent.getFinishReason().isNull);
    assert(absent.getFinishReasonCategory() == FinishReasonCategory.UNSPECIFIED);

    ChatGenerationMetadata unrecognized = new FixedFinishReasonMetadata(nullable("provider_specific"));
    assert(unrecognized.getFinishReason().get() == "provider_specific");
    assert(unrecognized.getFinishReasonCategory() == FinishReasonCategory.OTHER);
}

private final class FixedFinishReasonMetadata : ChatGenerationMetadata
{
    private Nullable!string finishReason_;

    this(Nullable!string finishReason)
    {
        finishReason_ = finishReason;
    }

    mixin ChatGenerationMetadata.Defaults;

    override Nullable!string getFinishReason()
    {
        return finishReason_;
    }
}
