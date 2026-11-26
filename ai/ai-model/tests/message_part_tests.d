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

// Ported from spring-ai v2.1.0, spring-ai-model/src/test/java/org/springframework/ai/chat/messages/part/MessagePartTests.java
// Modified by the Flint authors.
module message_part_tests;

import flint.ai.chat.messages.part : MessagePart, OpaquePayload, TextPart;
import flint.java.lang : IllegalArgumentException, NullPointerException, UnsupportedOperationException;
import flint.java.util : HashMap, Map;
import std.exception : assertThrown;
import std.typecons : Nullable, nullable;

@safe:

@("textPartOfHasNoPayloadAndEmptyAttributes")
unittest
{
    TextPart part = TextPart.of("hello");
    assert(part.text() == "hello");
    assert(part.payload().isNull);
    assert(part.attributes().isEmpty());
    assert(TextPart.of("").text() !is null);
}

@("whenTextIsNullThenThrow")
unittest
{
    assertThrown!IllegalArgumentException(new TextPart(null, Nullable!OpaquePayload.init, Map!(string, string).of()));
}

@("whenAttributesIsNullThenThrow")
unittest
{
    assertThrown!IllegalArgumentException(new TextPart("hello", Nullable!OpaquePayload.init, null));
}

@("attributesAreDefensivelyCopiedAndUnmodifiable")
unittest
{
    auto attributes = new HashMap!(string, string);
    attributes.put("partIndex", "0");

    TextPart part = new TextPart("hello", Nullable!OpaquePayload.init, attributes);
    attributes.put("partIndex", "9");

    assert(part.attributes().get("partIndex") == "0");
    assertThrown!UnsupportedOperationException(part.attributes().put("x", "y"));
}

@("text part replacements retain provider payload and use value equality")
unittest
{
    auto payload = nullable(OpaquePayload("anthropic", "signature", "sig-1"));
    auto original = new TextPart("hello", payload, Map!(string, string).of("partIndex", "0"));
    MessagePart view = original;
    auto replacement = cast(TextPart) view.withAttributes(Map!(string, string).of("partIndex", "1"));
    assert(replacement !is null && replacement !is original);
    assert(replacement.text() == "hello" && replacement.payload().get() == payload.get());
    assert(original.attributes().get("partIndex") == "0");
    assert(replacement.attributes().get("partIndex") == "1");
    auto equal = new TextPart("hello", payload, Map!(string, string).of("partIndex", "1"));
    assert(replacement == equal && replacement.hashCode() == equal.hashCode());
    assert(replacement != original);
    auto withoutPayload = new TextPart("hello", Nullable!OpaquePayload.init, original.attributes());
    assert(original != withoutPayload);
    assert(TextPart.of("hello") == TextPart.of("hello"));
    const payloadText = "OpaquePayload[provider=anthropic, kind=signature, data=sig-1]";
    assert(replacement.toString() == "TextPart[text=hello, payload=" ~ payloadText ~ ", attributes={partIndex=1}]");
}

@("text part rejects null values in its attribute snapshot")
unittest
{
    auto attributes = new HashMap!(string, string);
    attributes.put("missing", null);
    assertThrown!NullPointerException(new TextPart("hello", Nullable!OpaquePayload.init, attributes));
}

@("whenOpaquePayloadHasNullComponentThenThrow")
unittest
{
    try
        OpaquePayload("anthropic", "signature", null);
    catch (IllegalArgumentException error)
    {
        assert(error.msg == "data must not be null");
        return;
    }
    assert(false, "null payload data must be rejected");
}

@("opaque payload validation and lossless data")
unittest
{
    assertThrown!IllegalArgumentException(OpaquePayload("\u2003", "signature", ""));
    assertThrown!IllegalArgumentException(OpaquePayload("anthropic", " \t", ""));

    const empty = OpaquePayload("anthropic", "signature", "");
    assert(empty.provider() == "anthropic");
    assert(empty.kind() == "signature");
    assert(empty.data() !is null);
    assert(empty.data().length == 0);

    const payload = OpaquePayload("google", "thought_signature", "\0日本語\r\n");
    assert(payload.data() == "\0日本語\r\n");
    assert(payload == OpaquePayload("google", "thought_signature", "\0日本語\r\n"));
    assert(payload != OpaquePayload("anthropic", "thought_signature", "\0日本語\r\n"));
}
