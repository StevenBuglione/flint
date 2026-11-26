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
import flint.java.lang : IllegalArgumentException, NullPointerException;
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

@("systemMessageCopy")
unittest
{
    const text = "Tell me, did you sail across the sun?";
    auto metadata = Metadata.of("key", Any.of("value"));
    auto original = SystemMessage.builder().text(text).metadata(metadata).build();

    auto duplicate = original.copy();

    assert(duplicate.getText().get() == text);
    assert(duplicate.getMetadata().size() == 2 && duplicate.getMetadata() !is metadata);
}

@("systemMessageMutate")
unittest
{
    const text = "Tell me, did you sail across the sun?";
    auto metadata = Metadata.of("key", Any.of("value"));
    auto original = SystemMessage.builder().text(text).metadata(metadata).build();

    auto duplicate = original.mutate().build();

    assert(duplicate.getText().get() == text);
    assert(duplicate.getMetadata().size() == 2 && duplicate.getMetadata() !is metadata);

    const revisedText = "Farewell, Aragog!";
    auto revised = duplicate.mutate().text(revisedText).build();
    assert(revised.getText().get() == revisedText);
    assert(revised.getMetadata().size() == 2 && revised.getMetadata() !is duplicate.getMetadata());
}

@("systemMessageCopyPreservesImmutability")
unittest
{
    auto metadata = Metadata.of("key", Any.of("value"));
    auto original = SystemMessage.builder().text("Original text").metadata(metadata).build();
    auto duplicate = original.copy();

    assert(duplicate !is original);
    auto originalMetadata = original.getMetadata();
    auto copiedMetadata = duplicate.getMetadata();
    assert(copiedMetadata !is originalMetadata);
    assert(duplicate.getText().get() == original.getText().get());
    assert(copiedMetadata.equals(cast(Object) originalMetadata));
}

@("systemMessageMutateWithNewMetadata")
unittest
{
    const text = "Original text";
    auto original = SystemMessage.builder().text(text).metadata(Metadata.of("key1", Any.of("value1"))).build();

    auto revised = original.mutate().metadata(Metadata.of("key2", Any.of("value2"))).build();

    assert(revised.getText().get() == text);
    auto metadata = revised.getMetadata();
    assert(metadata.size() == 2 && !metadata.containsKey("key1"));
    assert(metadata.get(AbstractMessage.MESSAGE_TYPE).get!MessageType() == MessageType.SYSTEM);
    assert(metadata.get("key2").get!string() == "value2");
}

@("systemMessageMutateChaining")
unittest
{
    auto original = SystemMessage.builder().text("Original").metadata(Metadata.of("key1", Any.of("value1"))).build();

    auto revised = original.mutate().text("Updated").metadata(Metadata.of("key2", Any.of("value2"))).build();

    assert(revised.getText().get() == "Updated");
    auto metadata = revised.getMetadata();
    assert(metadata.size() == 2);
    assert(metadata.get(AbstractMessage.MESSAGE_TYPE).get!MessageType() == MessageType.SYSTEM);
    assert(metadata.get("key2").get!string() == "value2");
}

@("copy rejects null keys and values in the live metadata")
unittest
{
    auto messageWithNullKey = new SystemMessage(MessageText("original"));
    messageWithNullKey.getMetadata().put(null, Any.of("value"));
    assert(collectException!NullPointerException(messageWithNullKey.copy()) !is null);

    auto messageWithNullValue = new SystemMessage(MessageText("original"));
    messageWithNullValue.getMetadata().put("key", Any.init);
    assert(collectException!NullPointerException(messageWithNullValue.copy()) !is null);
}

@("mutate observes live metadata up to build and then snapshots it")
unittest
{
    auto original = new SystemMessage(MessageText("original"));
    auto builder = original.mutate();
    original.getMetadata().put("key", Any.of("before build"));
    auto revised = builder.build();
    original.getMetadata().put("key", Any.of("after build"));
    assert(revised.getMetadata().get("key").get!string() == "before build");
}

@("systemMessageEqualsAndHashCode")
unittest
{
    const text = "Test message";
    auto metadata = Metadata.of("key", Any.of("value"));
    auto first = SystemMessage.builder().text(text).metadata(metadata).build();
    auto second = SystemMessage.builder().text(text).metadata(metadata).build();

    assert(first == second);
    assert(first.hashCode() == second.hashCode());
}

@("systemMessageNotEqualsWithDifferentText")
unittest
{
    auto first = new SystemMessage(MessageText("Text 1"));
    auto second = new SystemMessage(MessageText("Text 2"));

    assert(first != second);
}
