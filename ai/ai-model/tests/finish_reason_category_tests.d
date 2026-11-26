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

// Ported from spring-ai v2.1.0, spring-ai-model/src/test/java/org/springframework/ai/chat/metadata/FinishReasonCategoryTests.java
// Modified by the Flint authors.
module finish_reason_category_tests;

import flint.ai.chat.metadata : FinishReasonCategory, categorize;
import std.typecons : Nullable, nullable;

@safe:

private alias Category = FinishReasonCategory;

@("shouldCategorizeCompletedReasons")
unittest
{
    foreach (reason; ["STOP", "stop", "end_turn", "END_TURN", "stop_sequence", "STOP_SEQUENCE"])
        assert(categorize(nullable(reason)) == Category.COMPLETED);
}

@("shouldCategorizeTruncatedReasons")
unittest
{
    foreach (reason; [
        "LENGTH", "length", "max_tokens", "MAX_TOKENS", "context_window_exceeded",
        "model_context_window_exceeded"
    ])
        assert(categorize(nullable(reason)) == Category.TRUNCATED);
}

@("shouldCategorizeToolCallReasons")
unittest
{
    foreach (reason; ["tool_calls", "TOOL_CALLS", "tool_call", "TOOL_CALL", "tool_use", "TOOL_USE"])
        assert(categorize(nullable(reason)) == Category.TOOL_CALL);
}

@("shouldCategorizeFilteredReasons")
unittest
{
    foreach (reason; [
        "content_filter", "CONTENT_FILTER", "safety", "SAFETY", "recitation", "RECITATION",
        "prohibited_content", "spii", "blocklist", "refusal", "guardrailRefusal"
    ])
        assert(categorize(nullable(reason)) == Category.FILTERED);
}

@("shouldCategorizeNullOrBlankAsUnknown")
unittest
{
    assert(categorize(Nullable!string.init) == Category.UNSPECIFIED);
    foreach (reason; ["", "   ", "\t", "\n"])
        assert(categorize(nullable(reason)) == Category.UNSPECIFIED);
}

@("shouldCategorizeUnrecognizedAsOther")
unittest
{
    foreach (reason; ["unknown_reason", "custom_stop", "model_specific", "foo_bar"])
        assert(categorize(nullable(reason)) == Category.OTHER);
}

@("absentReasonIsDistinctFromUnrecognizedReason")
unittest
{
    assert(categorize(Nullable!string.init) == Category.UNSPECIFIED);
    assert(categorize(nullable("")) == Category.UNSPECIFIED);
    assert(categorize(nullable("   ")) == Category.UNSPECIFIED);
    assert(categorize(nullable("not_a_known_reason")) == Category.OTHER);
}

@("shouldHandleMixedCaseAndWhitespace")
unittest
{
    assert(categorize(nullable("  STOP  ")) == Category.COMPLETED);
    assert(categorize(nullable("  End_Turn  ")) == Category.COMPLETED);
    assert(categorize(nullable("MAX_TOKENS")) == Category.TRUNCATED);
}

@("shouldReturnNonNullForAllEnumValues")
unittest
{
    // D enum values are never null. Keep Java's complete value set and its ordinal order.
    const values = [
        Category.COMPLETED, Category.TRUNCATED, Category.TOOL_CALL, Category.FILTERED,
        Category.OTHER, Category.UNSPECIFIED
    ];
    foreach (i, value; values)
        assert(cast(size_t) value == i);
}

@("categorize preserves Java blank, trim and root-locale lowercase semantics")
unittest
{
    assert(categorize(nullable("\u2003")) == Category.UNSPECIFIED);
    assert(categorize(nullable("\u2003STOP")) == Category.OTHER);
    assert(categorize(nullable("\u00a0")) == Category.OTHER);
    assert(categorize(nullable("\0")) == Category.OTHER);
    assert(categorize(nullable("\0STOP\x1f")) == Category.COMPLETED);
    assert(categorize(nullable("bloc\u212alist")) == Category.FILTERED);
    assert(categorize(nullable("SP\u0130I")) == Category.OTHER);
    assert(categorize(nullable("\u017ftop")) == Category.OTHER);
}
