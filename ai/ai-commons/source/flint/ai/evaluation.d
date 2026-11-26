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

// Ported from spring-ai v2.1.0, spring-ai-commons/src/main/java/org/springframework/ai/evaluation/EvaluationResponse.java
// Modified by the Flint authors.
module flint.ai.evaluation;

import flint.engine.aot.any : Any;
import flint.java.lang : Boolean, JavaObject, floatToString, stringHashCode;
import flint.java.util : Map;

@safe:

/// The outcome and associated metadata of an evaluation.
class EvaluationResponse
{
    private alias Metadata = Map!(string, Any);

    private bool pass_;
    private float score_;
    private string feedback_;
    private Metadata metadata_;

    /// Creates an evaluation response with its explicit score.
    this(bool pass, float score, string feedback, Metadata metadata) pure nothrow @nogc
    {
        pass_ = pass;
        score_ = score;
        feedback_ = feedback;
        metadata_ = metadata;
    }

    /// Creates an evaluation response with a zero score.
    this(bool pass, string feedback, Metadata metadata) pure nothrow @nogc
    {
        this(pass, 0.0f, feedback, metadata);
    }

    /// Whether the evaluation passed.
    bool isPass() const pure nothrow @nogc
    {
        return pass_;
    }

    /// Returns the score.
    float getScore() const pure nothrow @nogc
    {
        return score_;
    }

    /// Returns the feedback text.
    string getFeedback() const pure nothrow @nogc
    {
        return feedback_;
    }

    /// Returns the supplied metadata map.
    Metadata getMetadata()
    {
        return metadata_;
    }

    /// Compares all four fields using Java value semantics.
    bool equals(Object other)
    {
        if (this is other)
            return true;

        auto that = cast(EvaluationResponse) other;
        if (that is null || pass_ != that.pass_ || scoreBits(score_) != scoreBits(that.score_))
            return false;
        if ((feedback_ is null) != (that.feedback_ is null) || feedback_ != that.feedback_)
            return false;
        return metadata_ is that.metadata_ || (metadata_ !is null && metadata_.equals(cast(Object) that.metadata_));
    }

    /// Returns the Java array hash of the four boxed fields.
    int hashCode()
    {
        int hash = 31 + Boolean.hashCode(pass_);
        hash = 31 * hash + scoreBits(score_);
        hash = 31 * hash + stringHashCode(feedback_);
        return 31 * hash + (metadata_ is null ? 0 : metadata_.hashCode());
    }

    /// Returns the evaluation fields in the Java display format.
    override string toString()
    {
        const text = metadata_ is null ? null : metadata_.toString();
        return "EvaluationResponse{pass=" ~ Boolean.toString(pass_) ~ ", score=" ~ floatToString(
                score_) ~ ", feedback='" ~ (feedback_ is null
                ? "null" : feedback_) ~ "', metadata=" ~ (text is null ? "null" : text) ~ "}";
    }

    private static int scoreBits(float score) pure nothrow @nogc
    {
        union Bits
        {
            float value;
            uint pattern;
        }

        Bits bits = void;
        bits.value = score;
        // Float.floatToIntBits collapses all NaNs and preserves the sign of zero.
        return (bits.pattern & 0x7fff_ffffU) > 0x7f80_0000U ? 0x7fc0_0000 : cast(int) bits.pattern;
    }

    mixin JavaObject;
}
