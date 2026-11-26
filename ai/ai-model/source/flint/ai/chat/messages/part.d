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

// Ported from spring-ai v2.1.0, spring-ai-model/src/main/java/org/springframework/ai/chat/messages/part/{MessagePart,OpaquePayload,ReasoningPart,StreamingParts,TextPart,ToolResultPart,UnknownPart}.java
// Modified by the Flint authors.
module flint.ai.chat.messages.part;

import flint.ai.chat.messages.response_value : ToolResponse, joinRecord, normalizeText,
    recordText, sameText, textHash;
import flint.java.lang : IllegalArgumentException, JavaObject, NullPointerException, stringHashCode;
import flint.java.util : LinkedHashMap, List, Map;
import std.typecons : Nullable;

@safe:

private alias PartAttributes = Map!(string, string);
// Reuse the concrete map that Map.copyOf instantiates for part attributes.
private alias MutablePartAttributes = LinkedHashMap!(string, string);
private alias NullablePayload = Nullable!OpaquePayload;
private alias NullableText = Nullable!string;
private alias ResultParts = List!MessagePart;

// LDC's size profile needs the constructor inlined. DMD avoids importing its body in the caller.
version (LDC)
    private enum inlinePayloadConstructor = true;
else
    private enum inlinePayloadConstructor = false;

// The inlined constructor keeps its checks on the ordinary path and shares the failure code.
pragma(inline, false) private void invalidPayloadArgument(string message)
{
    throw new IllegalArgumentException(message);
}

// Collect the fragments on the stack and allocate only the returned string.
private string renderRecord(string prefix, string first, string secondLabel, string second,
        string thirdLabel, string third, string fourthLabel = "", string fourth = "") pure
{
    string[9] parts = [
        prefix, first, secondLabel, second, thirdLabel, third, fourthLabel, fourth, "]"
    ];
    return joinRecord(parts[]);
}

private PartAttributes copyAttributes(PartAttributes attributes)
{
    if (attributes is null)
        throw new IllegalArgumentException("attributes must not be null");
    attributes.forEach((string key, string value) {
        if (key is null || value is null)
            throw new NullPointerException();
    });
    return PartAttributes.copyOf(attributes);
}

private PartAttributes emptyPartAttributes()
{
    return PartAttributes.of();
}

// A null result means that no text parts were present.
package(flint.ai) string joinTextParts(ResultParts parts)
{
    string text;
    foreach (part; parts)
    {
        if (part is null)
            throw new NullPointerException();
        if (auto textPart = cast(TextPart) part)
        {
            if (text is null)
                text = textPart.text();
            else
                text ~= textPart.text();
        }
    }
    return text;
}

private bool samePayload(ref const NullablePayload left, ref const NullablePayload right)
{
    if (left.isNull)
        return right.isNull;
    return !right.isNull && left.get() == right.get();
}

private int payloadHash(ref const NullablePayload value)
{
    return value.isNull ? 0 : value.get().hashCode();
}

private string payloadText(ref const NullablePayload value)
{
    return value.isNull ? "null" : value.get().toString();
}

/// An ordered chat message part. Spring AI permits MediaPart, ReasoningPart,
/// TextPart, ToolCallPart, ToolResultPart and UnknownPart.
interface MessagePart
{
    /// Attribute identifying the provider that produced the part.
    enum string PROVIDER_ATTRIBUTE = "provider";

    /// Provider data to replay unchanged to its origin, when present.
    NullablePayload payload();

    /// Unmodifiable string attributes of the part.
    PartAttributes attributes();

    /// Creates a copy with the supplied attributes.
    MessagePart withAttributes(PartAttributes attributes);
}

/// Transport attributes for the content blocks of a streaming chat response.
final class StreamingParts
{
    /// Zero-based content block index.
    enum string PART_INDEX_ATTRIBUTE = "partIndex";

    /// Flag set to "true" for a delta.
    enum string PARTIAL_ATTRIBUTE = "partial";

    @disable this();

    /// Returns a copy marked as a delta of the indexed content block.
    static MessagePart partial(MessagePart part, int index)
    {
        return stamp(part, index, true);
    }

    /// Returns a copy of the complete indexed block with its partial flag removed.
    static MessagePart complete(MessagePart part, int index)
    {
        return stamp(part, index, false);
    }

    /// Returns whether the part carries the partial flag.
    static bool isPartial(MessagePart part)
    {
        import flint.java.lang : Boolean;

        return Boolean.parseBoolean(part.attributes().get(PARTIAL_ATTRIBUTE));
    }

    /// Removes the streaming attributes, preserving identity if neither is present.
    static MessagePart strip(MessagePart part)
    {
        auto attributes = part.attributes();
        if (!attributes.containsKey(PART_INDEX_ATTRIBUTE) && !attributes.containsKey(PARTIAL_ATTRIBUTE))
            return part;
        auto stripped = new MutablePartAttributes(attributes);
        stripped.remove(PART_INDEX_ATTRIBUTE);
        stripped.remove(PARTIAL_ATTRIBUTE);
        return part.withAttributes(stripped);
    }

    private static MessagePart stamp(MessagePart part, int index, bool partial)
    {
        import flint.java.lang : Integer;

        if (part is null)
            throw new IllegalArgumentException("part must not be null");
        if (index < 0)
            throw new IllegalArgumentException("index must not be negative");
        auto attributes = new MutablePartAttributes(part.attributes());
        attributes.put(PART_INDEX_ATTRIBUTE, Integer.toString(index));
        if (partial)
            attributes.put(PARTIAL_ATTRIBUTE, "true");
        else
            attributes.remove(PARTIAL_ATTRIBUTE);
        return part.withAttributes(attributes);
    }
}

/// Provider-owned data that a message part can carry back to its origin unchanged.
struct OpaquePayload
{
    private string provider_;
    private string kind_;
    private string data_;

    @disable this();

    /// Creates a payload from nonblank provider and kind names and a present data string.
    pragma(inline, inlinePayloadConstructor) this(string provider, string kind, string data)
    {
        import flint.util : StringUtils;

        if (!StringUtils.hasText(provider))
            invalidPayloadArgument("provider must not be empty");
        if (!StringUtils.hasText(kind))
            invalidPayloadArgument("kind must not be empty");
        if (data is null)
            invalidPayloadArgument("data must not be null");
        this.provider_ = provider;
        this.kind_ = kind;
        this.data_ = data;
    }

    /// The provider that produced the payload.
    string provider() const pure nothrow @nogc
    {
        return provider_;
    }

    /// The provider's name for this kind of payload.
    string kind() const pure nothrow @nogc
    {
        return kind_;
    }

    /// The payload string exactly as supplied by the provider adapter.
    string data() const pure nothrow @nogc
    {
        return data_;
    }

    /// Computes the Java record hash of the three components.
    int hashCode() const pure nothrow @nogc
    {
        return 31 * (31 * stringHashCode(provider_) + stringHashCode(kind_)) + stringHashCode(data_);
    }

    /// Formats the three record components.
    string toString() const
    {
        return renderRecord("OpaquePayload[provider=", provider_, ", kind=", kind_, ", data=", data_);
    }
}

/// A plain text message part (R16).
final class TextPart : MessagePart
{
    private string text_;
    private NullablePayload payload_;
    private PartAttributes attributes_;

    private this(string text)
    {
        if (text is null)
            throw new IllegalArgumentException("text must not be null");
        text_ = text;
    }

    /// Creates a part with a snapshot of its attributes.
    this(string text, NullablePayload payload, PartAttributes attributes)
    {
        this(text);
        payload_ = payload;
        attributes_ = copyAttributes(attributes);
    }

    /// Creates a text part with no provider payload or attributes.
    static TextPart of(string text)
    {
        auto part = new TextPart(text);
        part.attributes_ = emptyPartAttributes();
        return part;
    }

    /// The text, which may be empty.
    string text() const pure nothrow @nogc
    {
        return text_;
    }

    override NullablePayload payload()
    {
        return payload_;
    }

    override PartAttributes attributes()
    {
        return attributes_;
    }

    override TextPart withAttributes(PartAttributes attributes)
    {
        return new TextPart(text_, payload_, attributes);
    }

    /// Compares all three record components.
    bool equals(Object other)
    {
        auto that = cast(TextPart) other;
        return that !is null && text_ == that.text_ && samePayload(payload_, that.payload_)
            && attributes_.equals(cast(Object) that.attributes_);
    }

    /// Computes the Java record hash of the three components.
    int hashCode()
    {
        return 31 * (31 * stringHashCode(text_) + payloadHash(payload_)) + attributes_.hashCode();
    }

    /// Formats the three record components.
    override string toString()
    {
        return renderRecord("TextPart[text=", text_, ", payload=", payloadText(payload_),
                ", attributes=", attributes_.toString());
    }

    mixin JavaObject;
}

/// Provider reasoning and its optional replay payload (R16).
final class ReasoningPart : MessagePart
{
    private NullableText text_;
    private NullableText summary_;
    private NullablePayload payload_;
    private PartAttributes attributes_;

    private this(NullableText text)
    {
        text_ = text;
    }

    /// Creates a reasoning part with a snapshot of its attributes.
    this(NullableText text, NullableText summary, NullablePayload payload, PartAttributes attributes)
    {
        this(normalizeText(text));
        summary_ = normalizeText(summary);
        payload_ = payload;
        attributes_ = copyAttributes(attributes);
    }

    /// Creates a plain text reasoning part without provider data.
    static ReasoningPart of(string text)
    {
        if (text is null)
            throw new IllegalArgumentException("text must not be null");
        auto part = new ReasoningPart(NullableText(text));
        part.attributes_ = emptyPartAttributes();
        return part;
    }

    /// The human-readable reasoning, when supplied.
    NullableText text()
    {
        return text_;
    }

    /// The provider's summary, when supplied.
    NullableText summary()
    {
        return summary_;
    }

    override NullablePayload payload()
    {
        return payload_;
    }

    override PartAttributes attributes()
    {
        return attributes_;
    }

    override ReasoningPart withAttributes(PartAttributes attributes)
    {
        return new ReasoningPart(text_, summary_, payload_, attributes);
    }

    /// A provider payload can be replayed to the provider that owns it.
    bool replayableTo(string provider) const pure nothrow @nogc
    {
        return payload_.isNull || payload_.get().provider() == provider;
    }

    /// Compares the four record components.
    bool equals(Object other)
    {
        auto that = cast(ReasoningPart) other;
        return that !is null && sameText(text_, that.text_) && sameText(summary_, that.summary_)
            && samePayload(payload_, that.payload_) && attributes_.equals(cast(Object) that.attributes_);
    }

    /// Computes the Java record hash of the four components.
    int hashCode()
    {
        const contentHash = 31 * textHash(text_) + textHash(summary_);
        return 31 * (31 * contentHash + payloadHash(payload_)) + attributes_.hashCode();
    }

    /// Formats the four record components.
    override string toString()
    {
        return renderRecord("ReasoningPart[text=", recordText(text_), ", summary=", recordText(summary_),
                ", payload=", payloadText(payload_), ", attributes=", attributes_.toString());
    }

    mixin JavaObject;
}

/// A part whose provider or transport type is unknown to the adapter.
final class UnknownPart : MessagePart
{
    /// Provider identifier reserved for unrecognized Spring AI serialized types (R1).
    enum string FLINT_AI_PROVIDER = "spring-ai";

    private string provider_;
    private string kind_;
    private string rawJson_;
    private NullablePayload payload_;
    private PartAttributes attributes_;

    /// Creates an unknown part with its original JSON text and a snapshot of its attributes.
    this(string provider, string kind, string rawJson, NullablePayload payload, PartAttributes attributes)
    {
        import flint.util : Assert;

        Assert.hasText(provider, "provider must not be empty");
        Assert.hasText(kind, "kind must not be empty");
        Assert.isTrue(rawJson !is null, "rawJson must not be null");
        provider_ = provider;
        kind_ = kind;
        rawJson_ = rawJson;
        payload_ = payload;
        attributes_ = copyAttributes(attributes);
    }

    /// The producer of this part.
    string provider() const pure nothrow @nogc
    {
        return provider_;
    }

    /// The producer's discriminator for this part.
    string kind() const pure nothrow @nogc
    {
        return kind_;
    }

    /// This part's original JSON text.
    string rawJson() const pure nothrow @nogc
    {
        return rawJson_;
    }

    override NullablePayload payload()
    {
        return payload_;
    }

    override PartAttributes attributes()
    {
        return attributes_;
    }

    override UnknownPart withAttributes(PartAttributes attributes)
    {
        return new UnknownPart(provider_, kind_, rawJson_, payload_, attributes);
    }

    /// Compares all five record components.
    bool equals(Object other)
    {
        auto that = cast(UnknownPart) other;
        return that !is null && provider_ == that.provider_ && kind_ == that.kind_
            && rawJson_ == that.rawJson_ && samePayload(payload_, that.payload_)
            && attributes_.equals(cast(Object) that.attributes_);
    }

    /// Computes the Java record hash of the five components.
    int hashCode()
    {
        const discriminator = 31 * stringHashCode(provider_) + stringHashCode(kind_);
        const content = 31 * discriminator + stringHashCode(rawJson_);
        return 31 * (31 * content + payloadHash(payload_)) + attributes_.hashCode();
    }

    /// Formats the five record components.
    override string toString()
    {
        string[11] parts = [
            "UnknownPart[provider=", provider_, ", kind=", kind_, ", rawJson=", rawJson_,
            ", payload=", payloadText(payload_), ", attributes=", attributes_.toString(), "]"
        ];
        return joinRecord(parts[]);
    }

    mixin JavaObject;
}

/// The ordered result of a single tool call (R16).
final class ToolResultPart : MessagePart
{
    private NullableText id_;
    private NullableText name_;
    private ResultParts content_;
    private bool error_;
    private NullablePayload payload_;
    private PartAttributes attributes_;

    /// Captures the ordered content and attributes as unmodifiable snapshots.
    this(NullableText id, NullableText name, ResultParts content, bool isError, NullablePayload payload,
            PartAttributes attributes)
    {
        if (content is null)
            throw new IllegalArgumentException("content must not be null");
        if (attributes is null)
            throw new IllegalArgumentException("attributes must not be null");

        content_ = ResultParts.copyOf(content);
        foreach (part; content_)
            if (part is null)
                throw new NullPointerException();

        id_ = normalizeText(id);
        name_ = normalizeText(name);
        error_ = isError;
        payload_ = payload;
        attributes_ = copyAttributes(attributes);
    }

    /// The identifier of the corresponding tool call, when supplied.
    NullableText id()
    {
        return id_;
    }

    /// The tool name, when supplied.
    NullableText name()
    {
        return name_;
    }

    /// The content returned by the tool, in order.
    ResultParts content()
    {
        return content_;
    }

    /// Whether the tool reported an error.
    bool isError() const pure nothrow @nogc
    {
        return error_;
    }

    override NullablePayload payload()
    {
        return payload_;
    }

    override PartAttributes attributes()
    {
        return attributes_;
    }

    override ToolResultPart withAttributes(PartAttributes attributes)
    {
        return create(id_, name_, content_, error_, payload_, attributes);
    }

    /// Wraps a legacy response as a result, with one text part when it has a body.
    static ToolResultPart of(ToolResponse response)
    {
        const text = response.responseData();
        auto content = text.isNull ? ResultParts.of() : ResultParts.of(TextPart.of(text.get()));
        return create(response.id(), response.name(), content, false, NullablePayload.init, emptyPartAttributes());
    }

    /// Joins the text parts in order into a legacy response.
    ToolResponse toToolResponse()
    {
        return ToolResponse(id_, name_, NullableText(joinTextParts(content_)));
    }

    private static ToolResultPart create(NullableText id, NullableText name, ResultParts content,
            bool isError, NullablePayload payload, PartAttributes attributes)
    {
        return new ToolResultPart(id, name, content, isError, payload, attributes);
    }

    /// Compares the six record components.
    bool equals(Object other)
    {
        auto that = cast(ToolResultPart) other;
        return that !is null && sameText(id_, that.id_) && sameText(name_, that.name_)
            && content_.equals(cast(Object) that.content_) && error_ == that.error_
            && samePayload(payload_, that.payload_) && attributes_.equals(cast(Object) that.attributes_);
    }

    /// Hashes the six record components in Java order.
    int hashCode()
    {
        import flint.java.lang.boolean : Boolean;

        const callHash = 31 * textHash(id_) + textHash(name_);
        const contentHash = 31 * callHash + content_.hashCode();
        const resultHash = 31 * contentHash + Boolean.hashCode(error_);
        return 31 * (31 * resultHash + payloadHash(payload_)) + attributes_.hashCode();
    }

    /// Formats the six record components.
    override string toString()
    {
        string[13] parts = [
            "ToolResultPart[id=", recordText(id_), ", name=", recordText(name_), ", content=",
            content_.toString(), ", isError=", error_ ? "true" : "false", ", payload=",
            payloadText(payload_), ", attributes=", attributes_.toString(), "]"
        ];
        return joinRecord(parts[]);
    }

    mixin JavaObject;
}
