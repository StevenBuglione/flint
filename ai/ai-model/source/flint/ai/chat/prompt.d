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

// Ported from spring-ai v2.1.0, spring-ai-model/src/main/java/org/springframework/ai/chat/prompt/{ChatOptions,DefaultChatOptions}.java
// Modified by the Flint authors.
module flint.ai.chat.prompt;

import flint.ai.chat.messages.response_value : NullableText;
import flint.ai.model : ModelOptions;
import flint.java.lang : JavaObject;
import flint.java.util : List;
import std.typecons : Nullable;

@safe:

private alias ModelName = NullableText;
private alias Count = Nullable!int;
private alias Ratio = Nullable!double;
private alias StopSequences = List!string;

/// Options that can be shared across chat model providers.
interface ChatOptions : ModelOptions
{
    /// Returns the model name, when specified.
    ModelName getModel();

    /// Returns the frequency penalty, when specified.
    Ratio getFrequencyPenalty();

    /// Returns the maximum number of tokens, when specified.
    Count getMaxTokens();

    /// Returns the presence penalty, when specified.
    Ratio getPresencePenalty();

    /// Returns the stop sequences, or null when unspecified.
    StopSequences getStopSequences();

    /// Returns the temperature, when specified.
    Ratio getTemperature();

    /// Returns the top K, when specified.
    Count getTopK();

    /// Returns the top P, when specified.
    Ratio getTopP();

    /// Returns a new builder initialized with the values of these options.
    Builder mutate();

    /// Creates a builder for the default chat options.
    static Builder builder()
    {
        return new DefaultChatOptionsBuilder();
    }

    /// Fluent builder for chat options: the erased `Builder<B extends Builder<B>>` of the upstream API.
    interface Builder
    {
        /// Sets or clears the model name.
        Builder model(ModelName model);

        /// Sets or clears the frequency penalty.
        Builder frequencyPenalty(Ratio frequencyPenalty);

        /// Sets or clears the maximum number of tokens.
        Builder maxTokens(Count maxTokens);

        /// Sets or clears the presence penalty.
        Builder presencePenalty(Ratio presencePenalty);

        /// Sets or clears the stop sequences.
        Builder stopSequences(StopSequences stopSequences);

        /// Sets or clears the temperature.
        Builder temperature(Ratio temperature);

        /// Sets or clears the top K.
        Builder topK(Count topK);

        /// Sets or clears the top P.
        Builder topP(Ratio topP);

        /// Builds a chat options snapshot.
        ChatOptions build();

        /// Returns a copy of this builder that later changes to either do not affect.
        Builder clone();

        /// Merges the values the other builder set into this one, keeping this builder's where it set none.
        Builder combineWith(Builder other);
    }
}

/// A snapshot of common chat model options.
class DefaultChatOptions : ChatOptions
{
    private ModelName model_;
    private Ratio frequencyPenalty_;
    private Count maxTokens_;
    private Ratio presencePenalty_;
    private StopSequences stopSequences_;
    private Ratio temperature_;
    private Count topK_;
    private Ratio topP_;

    /// Captures the option values and an unmodifiable copy of the configured stops.
    protected this(ModelName model, Ratio frequencyPenalty, Count maxTokens, Ratio presencePenalty,
            StopSequences stopSequences, Ratio temperature, Count topK, Ratio topP)
    {
        import flint.ai.chat.messages.response_value : normalizeText;
        import flint.java.lang : NullPointerException;

        model_ = normalizeText(model);
        frequencyPenalty_ = frequencyPenalty;
        maxTokens_ = maxTokens;
        presencePenalty_ = presencePenalty;
        if (stopSequences !is null)
        {
            stopSequences_ = StopSequences.copyOf(stopSequences);
            // Java List.copyOf rejects null elements.
            foreach (sequence; stopSequences_)
                if (sequence is null)
                    throw new NullPointerException();
        }
        temperature_ = temperature;
        topK_ = topK;
        topP_ = topP;
    }

    /// Returns the captured model name.
    override ModelName getModel()
    {
        return model_;
    }

    /// Returns the captured frequency penalty.
    override Ratio getFrequencyPenalty()
    {
        return frequencyPenalty_;
    }

    /// Returns the captured maximum number of tokens.
    override Count getMaxTokens()
    {
        return maxTokens_;
    }

    /// Returns the captured presence penalty.
    override Ratio getPresencePenalty()
    {
        return presencePenalty_;
    }

    /// Returns the stop sequence snapshot, or null when unspecified.
    override StopSequences getStopSequences()
    {
        return stopSequences_;
    }

    /// Returns the captured temperature.
    override Ratio getTemperature()
    {
        return temperature_;
    }

    /// Returns the captured top K.
    override Count getTopK()
    {
        return topK_;
    }

    /// Returns the captured top P.
    override Ratio getTopP()
    {
        return topP_;
    }

    /// Returns a builder initialized with a copy of every captured value.
    override ChatOptions.Builder mutate()
    {
        return ChatOptions.builder().model(model_).frequencyPenalty(frequencyPenalty_).maxTokens(maxTokens_)
            .presencePenalty(presencePenalty_).stopSequences(stopSequences_)
            .temperature(temperature_).topK(topK_).topP(topP_);
    }

    /// Compares the captured values of options with the same runtime class.
    bool equals(Object other)
    {
        if (this is other)
            return true;
        auto that = cast(DefaultChatOptions) other;
        if (that is null || typeid(this) !is typeid(that))
            return false;

        return model_.isNull == that.model_.isNull && (model_.isNull
                || model_.get() == that.model_.get()) && sameRatio(frequencyPenalty_,
                that.frequencyPenalty_) && sameCount(maxTokens_,
                that.maxTokens_) && sameRatio(presencePenalty_, that.presencePenalty_)
            && (stopSequences_ is that.stopSequences_
                    || (stopSequences_ !is null && stopSequences_.equals(cast(Object) that.stopSequences_)))
            && sameRatio(temperature_,
                    that.temperature_) && sameCount(topK_, that.topK_) && sameRatio(topP_, that.topP_);
    }

    /// Hashes the captured fields in Java constructor order.
    int hashCode()
    {
        import flint.java.lang : stringHashCode;

        uint hash = 31 + (model_.isNull ? 0 : cast(uint) stringHashCode(model_.get()));
        hash = 31 * hash + ratioHash(frequencyPenalty_);
        hash = 31 * hash + (maxTokens_.isNull ? 0 : cast(uint) maxTokens_.get());
        hash = 31 * hash + ratioHash(presencePenalty_);
        hash = 31 * hash + (stopSequences_ is null ? 0 : cast(uint) stopSequences_.hashCode());
        hash = 31 * hash + ratioHash(temperature_);
        hash = 31 * hash + (topK_.isNull ? 0 : cast(uint) topK_.get());
        return cast(int)(31 * hash + ratioHash(topP_));
    }

    mixin JavaObject;
}

/// The default `ChatOptions.Builder` implementation: the erased `DefaultChatOptionsBuilder<B>`.
class DefaultChatOptionsBuilder : ChatOptions.Builder
{
    protected ModelName model_;
    protected Ratio frequencyPenalty_;
    protected Count maxTokens_;
    protected Ratio presencePenalty_;
    protected StopSequences stopSequences_;
    protected Ratio temperature_;
    protected Count topK_;
    protected Ratio topP_;

    /// Starts a builder with every setting absent.
    this()
    {
    }

    /// Returns this builder as its fluent type (the erased self type of the generic builder).
    protected ChatOptions.Builder self()
    {
        return this;
    }

    /// Sets or clears the model name.
    override ChatOptions.Builder model(ModelName model)
    {
        model_ = model;
        return this;
    }

    /// Sets or clears the frequency penalty.
    override ChatOptions.Builder frequencyPenalty(Ratio frequencyPenalty)
    {
        frequencyPenalty_ = frequencyPenalty;
        return this;
    }

    /// Sets or clears the maximum number of tokens.
    override ChatOptions.Builder maxTokens(Count maxTokens)
    {
        maxTokens_ = maxTokens;
        return this;
    }

    /// Sets or clears the presence penalty.
    override ChatOptions.Builder presencePenalty(Ratio presencePenalty)
    {
        presencePenalty_ = presencePenalty;
        return this;
    }

    /// Sets or clears the stop sequences, copying them like `new ArrayList<>(...)`.
    override ChatOptions.Builder stopSequences(StopSequences stopSequences)
    {
        stopSequences_ = stopSequences is null ? null : StopSequences.copyOf(stopSequences);
        return this;
    }

    /// Sets or clears the temperature.
    override ChatOptions.Builder temperature(Ratio temperature)
    {
        temperature_ = temperature;
        return this;
    }

    /// Sets or clears the top K.
    override ChatOptions.Builder topK(Count topK)
    {
        topK_ = topK;
        return this;
    }

    /// Sets or clears the top P.
    override ChatOptions.Builder topP(Ratio topP)
    {
        topP_ = topP;
        return this;
    }

    /// Builds a snapshot that survives later changes to this builder.
    override ChatOptions build()
    {
        return new DefaultChatOptions(model_, frequencyPenalty_, maxTokens_, presencePenalty_,
                stopSequences_, temperature_, topK_, topP_);
    }

    /// Returns a builder with a copy of every setting, including the stop sequences.
    override ChatOptions.Builder clone()
    {
        auto copy = new DefaultChatOptionsBuilder();
        copy.model_ = model_;
        copy.frequencyPenalty_ = frequencyPenalty_;
        copy.maxTokens_ = maxTokens_;
        copy.presencePenalty_ = presencePenalty_;
        copy.stopSequences_ = stopSequences_ is null ? null : StopSequences.copyOf(stopSequences_);
        copy.temperature_ = temperature_;
        copy.topK_ = topK_;
        copy.topP_ = topP_;
        return copy;
    }

    /// Merges the settings the other builder set, appending its stop sequences to this builder's.
    override ChatOptions.Builder combineWith(ChatOptions.Builder other)
    {
        auto that = cast(DefaultChatOptionsBuilder) other;
        if (that is null)
            return this;

        if (!that.model_.isNull)
            model_ = that.model_;
        if (!that.frequencyPenalty_.isNull)
            frequencyPenalty_ = that.frequencyPenalty_;
        if (!that.maxTokens_.isNull)
            maxTokens_ = that.maxTokens_;
        if (!that.presencePenalty_.isNull)
            presencePenalty_ = that.presencePenalty_;
        if (that.stopSequences_ !is null)
        {
            if (stopSequences_ is null)
                stopSequences_ = StopSequences.copyOf(that.stopSequences_);
            else
            {
                auto left = stopSequences_.toArray();
                auto right = that.stopSequences_.toArray();
                auto merged = new string[left.length + right.length];
                merged[0 .. left.length] = left[];
                merged[left.length .. $] = right[];
                stopSequences_ = StopSequences.of(merged);
            }
        }
        if (!that.temperature_.isNull)
            temperature_ = that.temperature_;
        if (!that.topK_.isNull)
            topK_ = that.topK_;
        if (!that.topP_.isNull)
            topP_ = that.topP_;
        return this;
    }
}

private bool sameCount(Count left, Count right)
{
    return left.isNull == right.isNull && (left.isNull || left.get() == right.get());
}

private bool sameRatio(Ratio left, Ratio right)
{
    import flint.java.lang : javaHashCode;

    if (left.isNull || right.isNull)
        return left.isNull == right.isNull;

    const a = left.get();
    const b = right.get();
    if (a != b)
        return a != a && b != b; // Java Double.equals treats all NaNs as equal.
    // Hash through one call site so both values share the template instance.
    uint[2] hashes;
    foreach (i, value; [a, b])
        hashes[i] = javaHashCode(value);
    return a != 0.0 || hashes[0] == hashes[1]; // Distinguish signed zeros.
}

private uint ratioHash(Ratio ratio)
{
    import flint.java.lang : javaHashCode;

    return ratio.isNull ? 0 : cast(uint) javaHashCode(ratio.get());
}
