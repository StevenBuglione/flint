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

// Ported from spring-ai v2.1.0, spring-ai-model/src/main/java/org/springframework/ai/chat/messages/part/{MessagePart,OpaquePayload,TextPart}.java
// Modified by the Flint authors.
module flint.ai.chat.messages.part;

import flint.java.lang : IllegalArgumentException, JavaObject, NullPointerException, stringHashCode;
import flint.java.util : Map;
import flint.util : Assert;
import std.typecons : Nullable;

@safe:

private alias PartAttributes = Map!(string, string);
private alias NullablePayload = Nullable!OpaquePayload;

// One concatenation per call, using the same implementation for both records.
private string renderRecord(string prefix, string first, string secondLabel, string second,
        string thirdLabel, string third)
{
    return prefix ~ first ~ secondLabel ~ second ~ thirdLabel ~ third ~ "]";
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

/// Provider-owned data that a message part can carry back to its origin unchanged.
struct OpaquePayload
{
    private string provider_;
    private string kind_;
    private string data_;

    @disable this();

    /// Creates a payload from nonblank provider and kind names and a present data string.
    this(string provider, string kind, string data)
    {
        Assert.hasText(provider, "provider must not be empty");
        Assert.hasText(kind, "kind must not be empty");
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
        if (attributes is null)
            throw new IllegalArgumentException("attributes must not be null");
        attributes.forEach((string key, string value) {
            if (key is null || value is null)
                throw new NullPointerException();
        });
        attributes_ = PartAttributes.copyOf(attributes);
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
        if (that is null || text_ != that.text_ || payload_.isNull != that.payload_.isNull)
            return false;
        if (!payload_.isNull && payload_.get() != that.payload_.get())
            return false;
        return attributes_.equals(cast(Object) that.attributes_);
    }

    /// Computes the Java record hash of the three components.
    int hashCode()
    {
        const payloadHash = payload_.isNull ? 0 : payload_.get().hashCode();
        return 31 * (31 * stringHashCode(text_) + payloadHash) + attributes_.hashCode();
    }

    /// Formats the three record components.
    override string toString()
    {
        const payloadText = payload_.isNull ? "null" : payload_.get().toString();
        return renderRecord("TextPart[text=", text_, ", payload=", payloadText, ", attributes=",
                attributes_.toString());
    }

    mixin JavaObject;
}
