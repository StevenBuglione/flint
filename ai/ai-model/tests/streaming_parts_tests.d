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

// Ported from spring-ai v2.1.0, spring-ai-model/src/test/java/org/springframework/ai/chat/messages/part/StreamingPartsTests.java
// Modified by the Flint authors.
module streaming_parts_tests;

import flint.ai.chat.messages.part : MessagePart, OpaquePayload, ReasoningPart, StreamingParts, TextPart;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : Map;
import std.exception : assertThrown;
import std.typecons : Nullable, nullable;

@safe:

private alias Attributes = Map!(string, string);

@("partial sets the raw index and flag on a text part")
unittest
{
    MessagePart part = StreamingParts.partial(TextPart.of("Hel"), 2);

    auto text = cast(TextPart) part;
    assert(text !is null && text.text() == "Hel");
    assert(StreamingParts.isPartial(part));
    assert(part.attributes().get(StreamingParts.PART_INDEX_ATTRIBUTE) == "2");
    assert(part.attributes().get(StreamingParts.PARTIAL_ATTRIBUTE) == "true");
}

@("completing a stamped part replaces the index and removes the flag")
unittest
{
    auto original = StreamingParts.partial(ReasoningPart.of("done"), 1);
    auto part = StreamingParts.complete(original, 0);

    assert(!StreamingParts.isPartial(part));
    assert(part.attributes().get(StreamingParts.PART_INDEX_ATTRIBUTE) == "0");
    assert(!part.attributes().containsKey(StreamingParts.PARTIAL_ATTRIBUTE));
    assert(StreamingParts.isPartial(original));
}

@("stampingPreservesOtherAttributesAndPayload")
unittest
{
    auto payload = nullable(OpaquePayload("anthropic", "signature", "sig"));
    auto original = new ReasoningPart(nullable("t"), Nullable!string.init, payload, Attributes.of("k", "v"));

    auto stamped = StreamingParts.partial(original, 1);

    assert(stamped.payload().get() == payload.get());
    assert(stamped.attributes().get("k") == "v");
    assert(original.attributes().size() == 1);
}

@("strip removes the index and flag and preserves other attributes")
unittest
{
    auto original = new TextPart("a", Nullable!OpaquePayload.init, Attributes.of("k", "v"));
    auto stamped = StreamingParts.partial(original, 3);

    auto stripped = cast(TextPart) StreamingParts.strip(stamped);

    assert(stripped == original);
    assert(!StreamingParts.isPartial(stripped));
    assert(StreamingParts.isPartial(stamped));
}

@("stripOfUnstampedPartIsSameValue")
unittest
{
    auto part = TextPart.of("a");
    assert(cast(TextPart) StreamingParts.strip(part) is part);
}

@("only case-insensitive true enables the partial flag")
unittest
{
    auto falsePart = new TextPart("a", Nullable!OpaquePayload.init,
            Attributes.of(StreamingParts.PARTIAL_ATTRIBUTE, "no"));
    assert(!StreamingParts.isPartial(falsePart));
    assert(StreamingParts.strip(falsePart).attributes().isEmpty());
    auto truePart = new TextPart("a", Nullable!OpaquePayload.init,
            Attributes.of(StreamingParts.PARTIAL_ATTRIBUTE, "TrUe"));
    assert(StreamingParts.isPartial(truePart));
}

@("stamping rejects a missing part and a negative index")
unittest
{
    assertThrown!IllegalArgumentException(StreamingParts.partial(null, 0));
    assertThrown!IllegalArgumentException(StreamingParts.complete(TextPart.of("a"), -1));
}
