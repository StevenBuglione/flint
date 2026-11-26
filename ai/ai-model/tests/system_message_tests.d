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
import flint.java.lang : IllegalArgumentException;
import std.exception : collectException;
import std.typecons : Nullable;

@safe:

private alias MessageText = Nullable!string;

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
