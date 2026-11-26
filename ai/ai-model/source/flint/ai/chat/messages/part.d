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

// Ported from spring-ai v2.1.0, spring-ai-model/src/main/java/org/springframework/ai/chat/messages/part/{MessagePart,OpaquePayload,ReasoningPart,StreamingParts,TextPart,UnknownPart}.java
// Modified by the Flint authors.
module flint.ai.chat.messages.part;

import core.exception : onOutOfMemoryError;
import flint.java.lang : IllegalArgumentException, JavaObject, NullPointerException, stringHashCode;
import flint.java.util : LinkedHashMap, Map;
import std.typecons : Nullable;

@safe:

private alias PartAttributes = Map!(string, string);
// Reuse the concrete map that Map.copyOf instantiates for part attributes.
private alias MutablePartAttributes = LinkedHashMap!(string, string);
private alias NullablePayload = Nullable!OpaquePayload;
private alias NullableText = Nullable!string;

// LDC's size profile needs the constructor inlined. DMD avoids importing its body in the caller.
version (LDC)
    private enum inlinePayloadConstructor = true;
else
    private enum inlinePayloadConstructor = false;

// Collect the fragments on the stack and allocate only the returned string.
private string renderRecord(string prefix, string first, string secondLabel, string second,
        string thirdLabel, string third, string fourthLabel = "", string fourth = "") pure
{
    string[9] parts = [
        prefix, first, secondLabel, second, thirdLabel, third, fourthLabel, fourth, "]"
    ];
    return joinRecord(parts[]);
}

package(flint.ai) char[] joinRecord(scope const(string)[] parts) pure
{
    size_t length;
    foreach (part; parts)
    {
        if (part.length > size_t.max - length)
            onOutOfMemoryError();
        length += part.length;
    }

    char[] result = new char[length];
    size_t offset;
    foreach (part; parts)
    {
        result[offset .. offset + part.length] = part;
        offset += part.length;
    }
    return result;
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

// Java has one null string value. A present empty string stays distinct (R5).
package(flint.ai) NullableText normalizeText(NullableText value) pure nothrow @nogc
{
    return value.isNull || value.get() is null ? NullableText.init : value;
}

package(flint.ai) bool sameText(ref const NullableText left, ref const NullableText right)
{
    if (left.isNull)
        return right.isNull;
    return !right.isNull && left.get() == right.get();
}

package(flint.ai) int textHash(ref const NullableText value)
{
    return value.isNull ? 0 : stringHashCode(value.get());
}

package(flint.ai) string recordText(ref const NullableText value)
{
    return value.isNull ? "null" : value.get();
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
            throw new IllegalArgumentException("provider must not be empty");
        if (!StringUtils.hasText(kind))
            throw new IllegalArgumentException("kind must not be empty");
        if (data is null)
            throw new IllegalArgumentException("data must not be null");
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
        part.attributes_ = PartAttributes.of();
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
        part.attributes_ = PartAttributes.of();
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
