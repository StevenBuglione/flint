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

// Ported from spring-ai v2.1.0, spring-ai-commons/src/main/java/org/springframework/ai/evaluation/{EvaluationRequest,EvaluationResponse,Evaluator}.java
// Modified by the Flint authors.
module flint.ai.evaluation;

import flint.ai.document : Document;
import flint.engine.aot.any : Any;
import flint.java.lang : Boolean, JavaObject, floatToString, stringHashCode;
import flint.java.util : List, Map;

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

private alias EvaluationDocuments = List!Document;

/// User text, supporting documents and the response to evaluate.
class EvaluationRequest
{
    private string userText_;
    private EvaluationDocuments dataList_;
    private string responseContent_;

    /// Creates a request with the shared empty document list.
    this(string userText, string responseContent)
    {
        import flint.java.util : Collections;

        this(userText, Collections.emptyList!Document(), responseContent);
    }

    /// Creates a request with empty user text.
    this(EvaluationDocuments dataList, string responseContent) pure nothrow @nogc
    {
        this("", dataList, responseContent);
    }

    /// Keeps the supplied document list by reference.
    this(string userText, EvaluationDocuments dataList, string responseContent) pure nothrow @nogc
    {
        userText_ = userText;
        dataList_ = dataList;
        responseContent_ = responseContent;
    }

    /// Returns the user's text.
    string getUserText() const pure nothrow @nogc
    {
        return userText_;
    }

    /// Returns the supplied supporting documents.
    EvaluationDocuments getDataList()
    {
        return dataList_;
    }

    /// Returns the response content to evaluate.
    string getResponseContent() const pure nothrow @nogc
    {
        return responseContent_;
    }

    /// Compares the request fields and supporting documents.
    bool equals(Object other)
    {
        if (this is other)
            return true;
        auto that = cast(EvaluationRequest) other;
        if (that is null || !sameEvaluationText(userText_, that.userText_)
                || !sameEvaluationText(responseContent_, that.responseContent_))
            return false;
        return dataList_ is that.dataList_ || (dataList_ !is null && dataList_.equals(cast(Object) that.dataList_));
    }

    /// Hashes the text, documents and response in Java field order.
    int hashCode()
    {
        int hash = 31 + stringHashCode(userText_);
        hash = 31 * hash + (dataList_ is null ? 0 : dataList_.hashCode());
        return 31 * hash + stringHashCode(responseContent_);
    }

    /// Renders the request fields in Java display format.
    override string toString()
    {
        const data = dataList_ is null ? "null" : dataList_.toString();
        return "EvaluationRequest{userText='" ~ (userText_ is null
                ? "null" : userText_) ~ "', dataList=" ~ data ~ ", chatResponse=" ~ (responseContent_ is null
                ? "null" : responseContent_) ~ "}";
    }

    mixin JavaObject;
}

private bool sameEvaluationText(string left, string right) pure nothrow @nogc
{
    return (left is null) == (right is null) && left == right;
}

/// Evaluates an AI response against an evaluation request.
interface Evaluator
{
    /// Evaluates the response.
    EvaluationResponse evaluate(EvaluationRequest request);

    /// Returns the request's nonblank supporting text in document order.
    string doGetSupportingData(EvaluationRequest request);

    /// Supplies the default supporting-text implementation (R3).
    mixin template Defaults(alias joinSupportingData = supportingData)
    {
        import flint.ai.evaluation : EvaluationRequest;

        override string doGetSupportingData(EvaluationRequest request)
        {
            return joinSupportingData(request);
        }
    }

    private static string supportingData(EvaluationRequest request)
    {
        import flint.ai.document : hasDocumentText;
        import flint.java.lang : NullPointerException;

        if (request is null)
            throw new NullPointerException();
        auto documents = request.getDataList();
        if (documents is null)
            throw new NullPointerException();

        version (Windows)
            enum separator = "\r\n";
        else
            enum separator = "\n";

        string result = "";
        foreach (document; documents)
        {
            if (document is null)
                throw new NullPointerException();
            const text = document.getText();
            if (text.isNull || !hasDocumentText(text.get()))
                continue;
            if (result.length != 0)
                result ~= separator;
            result ~= text.get();
        }
        return result;
    }
}
