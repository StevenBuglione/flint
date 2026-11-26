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

import flint.ai.chat.messages.part : MessagePart, OpaquePayload, ReasoningPart, TextPart, UnknownPart;
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

@("reasoningPartIsAMessagePart")
unittest
{
    const MessagePart part = ReasoningPart.of("thinking...");
    assert(cast(const ReasoningPart) part !is null);
}

@("reasoningPartOfIsPlainText")
unittest
{
    auto part = ReasoningPart.of("thinking...");
    assert(part.text().get() == "thinking...");
    assert(part.summary().isNull);
    assert(part.payload().isNull);
}

@("reasoningPartWithoutPayloadIsReplayableEverywhere")
unittest
{
    auto part = ReasoningPart.of("thinking...");
    assert(part.replayableTo("anthropic"));
    assert(part.replayableTo("openai"));
}

@("reasoningPartWithPayloadIsReplayableOnlyToItsProvider")
unittest
{
    auto payload = nullable(OpaquePayload("anthropic", "signature", "sig-1"));
    auto part = new ReasoningPart(nullable("thinking..."), Nullable!string.init, payload, Map!(string, string).of());
    assert(part.replayableTo("anthropic"));
    assert(!part.replayableTo("Anthropic"));
    assert(!part.replayableTo("openai"));
}

@("reasoningPartWithAttributesReturnsACopy")
unittest
{
    auto original = ReasoningPart.of("thinking...");
    auto part = original.withAttributes(Map!(string, string).of("k", "v"));
    assert(part !is original);
    assert(part.attributes().get("k") == "v");
    assert(part.text().get() == original.text().get());
    assert(original.attributes().isEmpty());
}

@("partsWithSameComponentsAreEqual")
unittest
{
    assert(TextPart.of("a") == TextPart.of("a"));
    assert(TextPart.of("a").hashCode() == TextPart.of("a").hashCode());
    auto payload = nullable(OpaquePayload("anthropic", "signature", "sig-1"));
    auto first = new ReasoningPart(nullable("t"), Nullable!string.init, payload, Map!(string, string).of());
    auto same = new ReasoningPart(nullable("t"), Nullable!string.init, payload, Map!(string, string).of());
    assert(first == same && first.hashCode() == same.hashCode());
    const payloadText = "OpaquePayload[provider=anthropic, kind=signature, data=sig-1]";
    assert(first.toString() == "ReasoningPart[text=t, summary=null, payload=" ~ payloadText ~ ", attributes={}]");
    auto emptySummary = new ReasoningPart(nullable("t"), nullable(""), payload, Map!(string, string).of());
    assert(first != emptySummary);
    assert(!TextPart.of("a").equals(ReasoningPart.of("a")));
}

@("reasoning part preserves the difference between null and empty text")
unittest
{
    auto attributes = Map!(string, string).of();
    Nullable!OpaquePayload payload;
    Nullable!string missing;
    auto wrappedNull = Nullable!string(cast(string) null);
    auto part = new ReasoningPart(wrappedNull, wrappedNull, payload, attributes);
    auto absent = new ReasoningPart(missing, missing, payload, attributes);
    auto empty = new ReasoningPart(nullable(""), nullable(""), payload, attributes);

    assert(part.text().isNull && part.summary().isNull);
    assert(part == absent && part.hashCode() == absent.hashCode());
    assert(part != empty);
    assert(!empty.text().isNull && !empty.summary().isNull);
    assert(part.toString() == "ReasoningPart[text=null, summary=null, payload=null, attributes={}]");
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

@("unknownPartKeepsRawJson")
unittest
{
    auto part = new UnknownPart("anthropic", "server_tool_use", `{"type":"server_tool_use"}`,
            Nullable!OpaquePayload.init, Map!(string, string).of());

    assert(part.provider() == "anthropic");
    assert(part.kind() == "server_tool_use");
    assert(part.rawJson() == `{"type":"server_tool_use"}`);
}

@("unknown part replacement preserves raw bytes and record semantics")
unittest
{
    enum raw = "{\r\n  \"type\" : \"未来\"\r\n}";
    auto payload = nullable(OpaquePayload("p", "k", "data"));
    auto attributes = new HashMap!(string, string);
    attributes.put("old", "value");
    auto original = new UnknownPart("p", "k", raw, payload, attributes);
    attributes.put("old", "changed");
    attributes.put("new", "value");

    MessagePart view = original;
    auto replacement = cast(UnknownPart) view.withAttributes(attributes);
    assert(replacement !is null && replacement !is original);
    attributes.put("new", "changed");
    assert(original.attributes().get("old") == "value");
    assert(!original.attributes().containsKey("new"));
    assert(replacement.attributes().get("new") == "value");
    assertThrown!UnsupportedOperationException(replacement.attributes().remove("old"));
    assert(replacement.rawJson() == raw);
    assert(replacement.payload().get() == payload.get());
    auto equal = new UnknownPart("p", "k", raw, payload, Map!(string, string).of("new", "value", "old", "changed"));
    assert(replacement == equal && replacement.hashCode() == equal.hashCode());
    assert(replacement != original);
    assert(replacement.toString() == "UnknownPart[provider=p, kind=k, rawJson=" ~ raw
            ~ ", payload=OpaquePayload[provider=p, kind=k, data=data], attributes={old=changed, new=value}]");
    assert(UnknownPart.FLINT_AI_PROVIDER == "spring-ai");
}

@("unknown parts reject missing constructor inputs and keep empty raw text")
unittest
{
    auto attributes = Map!(string, string).of();
    Nullable!OpaquePayload noPayload;
    assertThrown!IllegalArgumentException(new UnknownPart("\u2003", "k", "{}", noPayload, attributes));
    assertThrown!IllegalArgumentException(new UnknownPart("p", " ", "{}", noPayload, attributes));
    assertThrown!IllegalArgumentException(new UnknownPart("p", "k", null, noPayload, attributes));
    assertThrown!IllegalArgumentException(new UnknownPart("p", "k", "{}", noPayload, null));
    auto part = new UnknownPart("p", "k", "", noPayload, attributes);
    assert(part.rawJson() !is null && part.rawJson().length == 0);
    assert(part.payload().isNull);
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
