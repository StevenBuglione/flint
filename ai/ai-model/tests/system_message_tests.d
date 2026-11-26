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

// Ported from spring-ai v2.1.0, spring-ai-model/src/test/java/org/springframework/ai/chat/messages/SystemMessageTests.java
// Modified by the Flint authors.
module system_message_tests;

import flint.ai.chat.messages : AbstractMessage, MessageType, SystemMessage;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : Map;
import std.exception : collectException;
import std.typecons : Nullable;

@safe:

private alias MessageText = Nullable!string;
private alias Metadata = Map!(string, Any);

@("systemMessageWithNullText")
unittest
{
    assert(collectException!IllegalArgumentException(new SystemMessage(MessageText.init)) !is null);
}

@("systemMessageWithTextContent")
unittest
{
    const text = "Tell me, did you sail across the sun?";
    auto message = new SystemMessage(MessageText(text));
    assert(message.getText().get() == text);
    assert(message.getMetadata().get(AbstractMessage.MESSAGE_TYPE).get!MessageType() == MessageType.SYSTEM);
}

@("systemMessageWithEmptyText")
unittest
{
    auto message = new SystemMessage(MessageText(""));
    assert(message.getText().get() == "");
    assert(message.getMetadata().get(AbstractMessage.MESSAGE_TYPE).get!MessageType() == MessageType.SYSTEM);
}

@("systemMessageWithWhitespaceText")
unittest
{
    const text = "   \t\n   ";
    auto message = new SystemMessage(MessageText(text));
    assert(message.getText().get() == text);
    assert(message.getMetadata().get(AbstractMessage.MESSAGE_TYPE).get!MessageType() == MessageType.SYSTEM);
}

@("systemMessageFromBuilderWithText")
unittest
{
    const text = "Tell me, did you sail across the sun?";
    auto message = SystemMessage.builder().text(text).metadata(Metadata.of("key", Any.of("value"))).build();
    auto metadata = message.getMetadata();
    assert(message.getText().get() == text);
    assert(metadata.size() == 2);
    assert(metadata.get(AbstractMessage.MESSAGE_TYPE).get!MessageType() == MessageType.SYSTEM);
    assert(metadata.get("key").get!string() == "value");
}

@("systemMessageBuilderWithNullText")
unittest
{
    auto builder = SystemMessage.builder().text("previous").text(cast(string) null);
    assert(collectException!IllegalArgumentException(builder.build()) !is null);
}

@("systemMessageBuilderWithEmptyMetadata")
unittest
{
    const text = "Test message";
    auto message = SystemMessage.builder().text(text).metadata(Metadata.of()).build();
    auto metadata = message.getMetadata();
    assert(message.getText().get() == text);
    assert(metadata.size() == 1);
    assert(metadata.get(AbstractMessage.MESSAGE_TYPE).get!MessageType() == MessageType.SYSTEM);
}

@("systemMessageBuilderOverwriteMetadata")
unittest
{
    const text = "Test message";
    auto message = SystemMessage.builder().text(text).metadata(Metadata.of("key1",
            Any.of("value1"))).metadata(Metadata.of("key2", Any.of("value2"))).build();
    auto metadata = message.getMetadata();
    assert(metadata.size() == 2);
    assert(metadata.get(AbstractMessage.MESSAGE_TYPE).get!MessageType() == MessageType.SYSTEM);
    assert(metadata.get("key2").get!string() == "value2");
    assert(!metadata.containsKey("key1"));
}

@("default builder metadata is empty and explicit null metadata is invalid")
unittest
{
    SystemMessage.Builder builder;
    builder.text(MessageText(""));
    auto message = builder.build();
    assert(!message.getText().isNull && message.getText().get().length == 0);
    assert(message.getMetadata().size() == 1);
    builder.metadata(null);
    const failure = collectException!IllegalArgumentException(builder.build());
    assert(failure !is null && failure.msg == "Metadata must not be null");
}
