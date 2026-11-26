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

import flint.ai.chat.messages.part : OpaquePayload;
import flint.java.lang : IllegalArgumentException;
import std.exception : assertThrown;

@safe:

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
