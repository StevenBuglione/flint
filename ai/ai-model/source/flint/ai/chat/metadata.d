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

// Ported from spring-ai v2.1.0, spring-ai-model/src/main/java/org/springframework/ai/chat/metadata/{ChatGenerationMetadata,DefaultUsage,EmptyRateLimit,FinishReasonCategory,RateLimit,Usage}.java
// Modified by the Flint authors.
module flint.ai.chat.metadata;

import flint.ai.model : ResultMetadata;
import flint.engine.aot.any : Any;
import flint.java.lang : JavaObject;
import flint.java.time : Duration;
import std.typecons : Nullable;

@safe:

private alias LongCount = Nullable!long;
private alias TokenCount = Nullable!int;
private alias ResetTime = Nullable!Duration;

/// A provider's request and token rate limits, balance, and time until reset.
/// A provider may omit a measurement. An empty Nullable represents an omitted value (R5).
interface RateLimit
{
    /// Maximum number of requests allowed by the current limit.
    LongCount getRequestsLimit();

    /// Requests remaining before the limit is exhausted.
    LongCount getRequestsRemaining();

    /// Time until the request limit resets.
    ResetTime getRequestsReset();

    /// Maximum number of tokens allowed by the current limit.
    LongCount getTokensLimit();

    /// Tokens remaining before the limit is exhausted.
    LongCount getTokensRemaining();

    /// Time until the token limit resets.
    ResetTime getTokensReset();
}

/// A RateLimit with present zero values for every property.
class EmptyRateLimit : RateLimit
{
    /// Creates a zero-valued rate limit.
    this() pure nothrow @nogc
    {
    }

    override LongCount getRequestsLimit() pure nothrow @nogc
    {
        return LongCount(0);
    }

    override LongCount getRequestsRemaining() pure nothrow @nogc
    {
        return LongCount(0);
    }

    override ResetTime getRequestsReset() pure nothrow @nogc
    {
        return ResetTime(Duration.ZERO);
    }

    override LongCount getTokensLimit() pure nothrow @nogc
    {
        return LongCount(0);
    }

    override LongCount getTokensRemaining() pure nothrow @nogc
    {
        return LongCount(0);
    }

    override ResetTime getTokensReset() pure nothrow @nogc
    {
        return ResetTime(Duration.ZERO);
    }
}

/// Provider-neutral categories for chat completion finish reasons.
enum FinishReasonCategory
{
    /// The model finished normally.
    COMPLETED,
    /// A length or token limit stopped output.
    TRUNCATED,
    /// The provider reported tool invocation.
    TOOL_CALL,
    /// A safety or policy filter stopped output.
    FILTERED,
    /// The provider supplied an unrecognized reason.
    OTHER,
    /// The provider supplied no reason.
    UNSPECIFIED,
}

/// Classifies an optional provider finish reason using Spring AI's aliases (R5, R20).
FinishReasonCategory categorize(Nullable!string rawReason) pure nothrow @nogc
{
    import flint.util : StringUtils;

    if (rawReason.isNull || !StringUtils.hasText(rawReason.get()))
        return FinishReasonCategory.UNSPECIFIED;

    string reason = rawReason.get();
    // Java's trim removes ASCII control characters and space. isBlank uses Unicode whitespace.
    while (reason.length && reason[0] <= ' ')
        reason = reason[1 .. $];
    while (reason.length && reason[$ - 1] <= ' ')
        reason = reason[0 .. $ - 1];

    char["model_context_window_exceeded".length] normalized;
    size_t length;
    for (size_t start; start < reason.length;)
    {
        if (length == normalized.length)
            return FinishReasonCategory.OTHER;

        char letter = reason[start++];
        if (letter >= 'A' && letter <= 'Z')
            letter = cast(char)(letter + ('a' - 'A'));
        else if (letter >= 0x80)
        {
            // All aliases are ASCII. Kelvin sign is the only non-ASCII scalar that
            // lowercases to one ASCII letter in Locale.ROOT.
            enum kelvin = "\u212a";
            const offset = start - 1;
            if (reason.length - offset < kelvin.length || reason[offset .. offset + kelvin.length] != kelvin)
                return FinishReasonCategory.OTHER;
            letter = 'k';
            start = offset + kelvin.length;
        }
        normalized[length++] = letter;
    }
    return finishReasonAlias(normalized[0 .. length]);
}

private FinishReasonCategory finishReasonAlias(scope const(char)[] reason) pure nothrow @nogc
{
    switch (reason)
    {
    case "stop", "end_turn", "stop_sequence":
        return FinishReasonCategory.COMPLETED;
    case "length", "max_tokens", "context_window_exceeded",
            "model_context_window_exceeded":
            return FinishReasonCategory.TRUNCATED;
    case "tool_calls", "tool_call", "tool_use":
        return FinishReasonCategory.TOOL_CALL;
    case "content_filter", "safety", "recitation", "prohibited_content", "spii", "blocklist",
            "refusal", "guardrailrefusal":
            return FinishReasonCategory.FILTERED;
    default:
        return FinishReasonCategory.OTHER;
    }
}

/// Metadata associated with the generation of a chat response.
interface ChatGenerationMetadata : ResultMetadata
{
    /// The provider's raw finish reason, which may be absent.
    Nullable!string getFinishReason();

    /// The provider-neutral finish reason.
    FinishReasonCategory getFinishReasonCategory();

    /// Fallback for implementations without a provider-specific category (R3).
    mixin template Defaults()
    {
        override FinishReasonCategory getFinishReasonCategory()
        {
            import flint.ai.chat.metadata : categorize;

            return categorize(getFinishReason());
        }
    }
}

/// The token counts and native provider usage for a model request.
interface Usage
{
    /// Returns the prompt token count, when available (R5).
    TokenCount getPromptTokens();

    /// Returns the completion token count, when available (R5).
    TokenCount getCompletionTokens();

    /// Returns the total number of tokens used for the request.
    int getTotalTokens();

    /// Returns the provider's usage data. An empty Any represents absent data.
    Any getNativeUsage();

    /// Returns the number of tokens read from the prompt cache, when available (R5).
    LongCount getCacheReadInputTokens();

    /// Returns the number of tokens written to the prompt cache, when available (R5).
    LongCount getCacheWriteInputTokens();

    /// Computes the default total and leaves cache counts absent (R3).
    mixin template Defaults()
    {
        import std.typecons : Nullable;

        override int getTotalTokens()
        {
            const int prompt = getPromptTokens().get(0);
            const int completion = getCompletionTokens().get(0);
            // Adding as uint preserves Java's two's-complement overflow.
            return cast(int)(cast(uint) prompt + cast(uint) completion);
        }

        override Nullable!long getCacheReadInputTokens() pure nothrow @nogc
        {
            return Nullable!long.init;
        }

        override Nullable!long getCacheWriteInputTokens() pure nothrow @nogc
        {
            return Nullable!long.init;
        }
    }
}

/// Token counts and optional provider data from a model invocation.
class DefaultUsage : Usage
{
    private int prompt_;
    private int completion_;
    private int total_;
    private Any native_;
    private LongCount cacheRead_;
    private LongCount cacheWrite_;

    /// Creates usage with a total computed from the prompt and completion counts.
    this(TokenCount promptTokens, TokenCount completionTokens) pure nothrow @nogc
    {
        this(promptTokens, completionTokens, TokenCount.init, Any.init);
    }

    /// Creates usage with an explicit total, or computes it if absent.
    this(TokenCount promptTokens, TokenCount completionTokens, TokenCount totalTokens) pure nothrow @nogc
    {
        this(promptTokens, completionTokens, totalTokens, Any.init);
    }

    /// Creates usage with optional native provider data.
    this(TokenCount promptTokens, TokenCount completionTokens, TokenCount total, Any nativeUsage) pure nothrow @nogc
    {
        this(promptTokens, completionTokens, total, nativeUsage, LongCount.init, LongCount.init);
    }

    /// Creates usage with provider data and optional prompt cache counts.
    this(TokenCount promptTokens, TokenCount completionTokens, TokenCount totalTokens, Any nativeUsage,
            LongCount cacheReadInputTokens, LongCount cacheWriteInputTokens) pure nothrow @nogc
    {
        prompt_ = promptTokens.isNull ? 0 : promptTokens.get();
        completion_ = completionTokens.isNull ? 0 : completionTokens.get();
        total_ = totalTokens.isNull ? cast(int)(cast(uint) prompt_ + cast(uint) completion_) : totalTokens.get();
        native_ = nativeUsage;
        cacheRead_ = cacheReadInputTokens;
        cacheWrite_ = cacheWriteInputTokens;
    }

    override TokenCount getPromptTokens() pure nothrow @nogc
    {
        return TokenCount(prompt_);
    }

    override TokenCount getCompletionTokens() pure nothrow @nogc
    {
        return TokenCount(completion_);
    }

    override int getTotalTokens() pure nothrow @nogc
    {
        return total_;
    }

    override Any getNativeUsage() pure nothrow @nogc
    {
        return native_;
    }

    override LongCount getCacheReadInputTokens() pure nothrow @nogc
    {
        return cacheRead_;
    }

    override LongCount getCacheWriteInputTokens() pure nothrow @nogc
    {
        return cacheWrite_;
    }

    /// Compares counts and native data for objects of the same concrete class.
    bool equals(Object other)
    {
        auto that = cast(DefaultUsage) other;
        return this is that || (that !is null && typeid(this) is typeid(that) && prompt_ == that.prompt_
                && completion_ == that.completion_ && total_ == that.total_ && sameCacheCount(cacheRead_,
                    that.cacheRead_) && sameCacheCount(cacheWrite_, that.cacheWrite_)
                && equalNativeUsage(native_, that.native_));
    }

    /// Combines the hashes of the counts and native data.
    int hashCode()
    {
        import flint.java.lang : Long;

        const int read = cacheRead_.isNull ? 0 : Long.hashCode(cacheRead_.get());
        const int written = cacheWrite_.isNull ? 0 : Long.hashCode(cacheWrite_.get());
        int result = 31 * (31 * prompt_ + completion_) + total_;
        result = 31 * result + hashNativeUsage(native_);
        return 31 * (31 * result + read) + written;
    }

    /// Formats counts and any available cache fields.
    override string toString()
    {
        import flint.ai.chat.messages.response_value : joinRecord;
        import flint.engine.aot.text : decimal;

        const bool hasRead = !cacheRead_.isNull;
        const bool hasWritten = !cacheWrite_.isNull;
        string[11] parts = [
            "DefaultUsage{promptTokens=", decimal(prompt_), ", completionTokens=",
            decimal(completion_), ", totalTokens=", decimal(total_),
            hasRead ? ", cacheReadInputTokens=" : "", hasRead ? decimal(cacheRead_.get()) : "",
            hasWritten ? ", cacheWriteInputTokens=" : "", hasWritten ? decimal(cacheWrite_.get()) : "",
            "}"
        ];
        return joinRecord(parts[]);
    }

    mixin JavaObject;
}

private bool sameCacheCount(ref const LongCount left, ref const LongCount right) pure nothrow @nogc
{
    if (left.isNull)
        return right.isNull;
    return !right.isNull && left.get() == right.get();
}

private bool equalNativeUsage(ref Any left, ref Any right)
{
    import flint.engine.aot.objects : objectEquals;

    if (left.isNull() || right.isNull())
        return left.isNull() && right.isNull();
    auto leftObject = left.asObject();
    auto rightObject = right.asObject();
    if (leftObject !is null || rightObject !is null)
        return objectEquals(leftObject, rightObject);
    return left == right;
}

private int hashNativeUsage(ref Any value)
{
    import flint.engine.aot.objects : objectToHash;

    if (value.isNull())
        return 0;
    if (auto object = value.asObject())
        return cast(int) objectToHash(object);
    return cast(int) value.toHash();
}
