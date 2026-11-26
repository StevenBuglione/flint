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

module message_contract_tests;

import flint.ai.chat.messages : Message, MessageType;
import flint.ai.content : Content;
import flint.engine.aot.any : Any;
import flint.java.util : HashMap, Map;
import std.typecons : Nullable;

@safe:

private alias Metadata = Map!(string, Any);

private final class TestMessage : Message
{
    Metadata metadata;

    this(Metadata metadata)
    {
        this.metadata = metadata;
    }

    override Nullable!string getText()
    {
        return Nullable!string("");
    }

    override Metadata getMetadata()
    {
        return metadata;
    }

    override MessageType getMessageType()
    {
        return MessageType.SYSTEM;
    }
}

@("chat messages preserve their role and inherited content dispatch")
unittest
{
    auto metadata = new HashMap!(string, Any)();
    metadata.put("source", Any.of("fixture"));
    Message message = new TestMessage(metadata);
    Content content = message;
    assert(message.getMessageType() == MessageType.SYSTEM);
    const text = content.getText();
    assert(!text.isNull && text.get().length == 0);
    assert(content.getMetadata() is metadata);
}
