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

import flint.ai.model : ModelOptions;
import flint.java.lang : JavaObject;
import flint.java.util : List;
import std.typecons : Nullable;

@safe:

private alias ModelName = Nullable!string;
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
        import flint.java.lang : NullPointerException;

        model_ = model;
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
    return a != 0.0 || javaHashCode(a) == javaHashCode(b); // Distinguish signed zeros.
}

private uint ratioHash(Ratio ratio)
{
    import flint.java.lang : javaHashCode;

    return ratio.isNull ? 0 : cast(uint) javaHashCode(ratio.get());
}
