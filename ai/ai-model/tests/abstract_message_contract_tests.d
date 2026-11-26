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

module abstract_message_contract_tests;

import flint.ai.chat.messages : AbstractMessage, Message, MessageType, SystemMessage;
import flint.ai.chat.messages.part : MessagePart, TextPart, ReasoningPart;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException, NullPointerException, UnsupportedOperationException;
import flint.java.util : ArrayList, HashMap, List, Map;
import std.exception : collectException;
import std.typecons : Nullable;

@safe:

private alias Text = Nullable!string;
private alias Parts = List!MessagePart;
private alias Metadata = Map!(string, Any);
private alias MutableMetadata = HashMap!(string, Any);

private final class FixtureMessage : AbstractMessage
{
    this(MessageType role, Text text, Metadata metadata)
    {
        super(role, text, metadata);
    }

    this(MessageType role, Parts parts, Metadata metadata)
    {
        super(role, parts, metadata);
    }
}

@("legacy message construction distinguishes absent and present empty text")
unittest
{
    auto metadata = new MutableMetadata();
    auto absent = new FixtureMessage(MessageType.ASSISTANT, Text.init, metadata);
    assert(absent.getText().isNull && absent.getParts().isEmpty());
    auto present = new FixtureMessage(MessageType.SYSTEM, Text(""), metadata);
    assert(!present.getText().isNull && present.getText().get().length == 0);
    assert(present.getParts().size() == 1 && (cast(TextPart) present.getParts().get(0)).text() == "");
    const user = MessageType.USER;
    const failure = collectException!IllegalArgumentException(new FixtureMessage(user, Text.init, metadata));
    assert(failure !is null && failure.msg == "Content must not be null for SYSTEM or USER messages");
}

@("message parts are snapshotted, and their text is joined in order")
unittest
{
    auto parts = new ArrayList!MessagePart();
    auto leading = TextPart.of("元");
    parts.add(leading);
    parts.add(ReasoningPart.of("hidden"));
    parts.add(TextPart.of("😀"));
    auto message = new FixtureMessage(MessageType.USER, parts, new MutableMetadata());
    assert(message.getText().get() == "元😀");
    parts.set(0, TextPart.of("changed"));
    assert(message.getParts().get(0) is leading);
    assert(collectException!UnsupportedOperationException(message.getParts().clear()) !is null);

    parts.clear();
    parts.add(ReasoningPart.of("hidden"));
    auto reasoningOnly = new FixtureMessage(MessageType.ASSISTANT, parts, new MutableMetadata());
    assert(!reasoningOnly.getText().isNull && reasoningOnly.getText().get().length == 0);
}

@("message metadata is copied and the role entry uses the message type")
unittest
{
    auto metadata = new MutableMetadata();
    metadata.put(AbstractMessage.MESSAGE_TYPE, Any.of("old-role"));
    metadata.put("source", Any.of("fixture"));
    Message message = new FixtureMessage(MessageType.SYSTEM, Text("instruction"), metadata);
    assert(message.getMessageType() == MessageType.SYSTEM);
    auto result = message.getMetadata();
    assert(result !is metadata);
    assert(result.get(AbstractMessage.MESSAGE_TYPE).get!MessageType() == MessageType.SYSTEM);
    metadata.put("source", Any.of("changed"));
    assert(result.get("source").get!string() == "fixture");
}

@("message construction rejects null collections and null part entries")
unittest
{
    auto metadata = new MutableMetadata();
    const noParts = collectException!IllegalArgumentException(new FixtureMessage(MessageType.ASSISTANT,
            cast(Parts) null, metadata));
    assert(noParts !is null && noParts.msg == "Parts must not be null");
    const noMetadata = collectException!IllegalArgumentException(new FixtureMessage(MessageType.ASSISTANT,
            Text.init, null));
    assert(noMetadata !is null && noMetadata.msg == "Metadata must not be null");
    auto parts = new ArrayList!MessagePart();
    parts.add(null);
    assert(collectException!NullPointerException(new FixtureMessage(MessageType.ASSISTANT, parts, metadata)) !is null);
}

@("message equality works across subtypes and compares live metadata")
unittest
{
    AbstractMessage normal = new SystemMessage(Text("instruction"));
    AbstractMessage fixture = new FixtureMessage(MessageType.SYSTEM, Text("instruction"), new MutableMetadata());
    assert(normal.equals(fixture) && fixture.equals(normal));
    assert(normal.hashCode() == fixture.hashCode());
    assert(normal.equals(normal) && !normal.equals(null) && !normal.equals(new Object()));

    fixture.getMetadata().put("source", Any.of("different"));
    assert(!normal.equals(fixture));
}

@("message equality distinguishes the role and ordered part values")
unittest
{
    auto metadata = new MutableMetadata();
    auto firstParts = Parts.of(TextPart.of("a"), TextPart.of("aa"));
    auto secondParts = Parts.of(TextPart.of("aa"), TextPart.of("a"));
    auto first = new FixtureMessage(MessageType.SYSTEM, firstParts, metadata);
    auto second = new FixtureMessage(MessageType.SYSTEM, secondParts, metadata);
    assert(first.getText().get() == second.getText().get());
    assert(!first.equals(second));

    auto samePartsOtherRole = new FixtureMessage(MessageType.USER, firstParts, metadata);
    samePartsOtherRole.getMetadata().put(AbstractMessage.MESSAGE_TYPE, Any.of(MessageType.SYSTEM));
    assert(first.getMetadata().equals(cast(Object) samePartsOtherRole.getMetadata()));
    assert(!first.equals(samePartsOtherRole));
}
