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

// Ported from spring-ai v2.1.0, spring-ai-model/src/main/java/org/springframework/ai/chat/messages/AssistantMessage.java
// Modified by the Flint authors.
/// Internal record exported as AssistantMessage.ToolCall.
module flint.ai.chat.messages.tool_call_value;

import flint.ai.chat.messages.response_value : NullableText, joinRecord, normalizeText,
    recordText, sameText, textHash;
import flint.java.lang : JavaObject;

@safe:

/// Legacy tool call requested by the model.
struct ToolCall
{
    private NullableText id_;
    private NullableText type_;
    private NullableText name_;
    private NullableText arguments_;

    /// Creates a call from its ID, type, name and arguments.
    this(NullableText id, NullableText type, NullableText name, NullableText arguments) pure nothrow @nogc
    {
        id_ = normalizeText(id);
        type_ = normalizeText(type);
        name_ = normalizeText(name);
        arguments_ = normalizeText(arguments);
    }

    /// The identifier that ties the call to its response.
    NullableText id() const pure nothrow @nogc
    {
        return id_;
    }

    /// The provider's call type.
    NullableText type() const pure nothrow @nogc
    {
        return type_;
    }

    /// The name of the requested tool.
    NullableText name() const pure nothrow @nogc
    {
        return name_;
    }

    /// The argument string supplied by the model.
    NullableText arguments() const pure nothrow @nogc
    {
        return arguments_;
    }

    /// Compares the four record components.
    bool equals(const ToolCall other) const
    {
        return sameText(id_, other.id_) && sameText(type_, other.type_) && sameText(name_,
                other.name_) && sameText(arguments_, other.arguments_);
    }

    /// Hashes the four record components in Java order.
    int hashCode() const
    {
        int hash = 31 * textHash(id_) + textHash(type_);
        hash = 31 * hash + textHash(name_);
        return 31 * hash + textHash(arguments_);
    }

    /// Formats the four record components in declaration order.
    string toString() const
    {
        string[9] parts = [
            "ToolCall[id=", recordText(id_), ", type=", recordText(type_), ", name=",
            recordText(name_), ", arguments=", recordText(arguments_), "]"
        ];
        return joinRecord(parts[]);
    }

    mixin JavaObject;
}
