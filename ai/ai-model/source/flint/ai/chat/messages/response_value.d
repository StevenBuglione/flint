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

// Ported from spring-ai v2.1.0, spring-ai-model/src/main/java/org/springframework/ai/chat/messages/ToolResponseMessage.java
// Modified by the Flint authors.
/// Internal record support shared by the message and part modules.
module flint.ai.chat.messages.response_value;

import core.exception : onOutOfMemoryError;
import flint.java.lang : JavaObject, stringHashCode;
import std.typecons : Nullable;

@safe:

package(flint.ai) alias NullableText = Nullable!string;

package(flint.ai) char[] joinRecord(scope const(string)[] parts) pure
{
    size_t length;
    foreach (part; parts)
    {
        if (part.length > size_t.max - length)
            onOutOfMemoryError();
        length += part.length;
    }

    char[] result = new char[length];
    size_t offset;
    foreach (part; parts)
    {
        result[offset .. offset + part.length] = part;
        offset += part.length;
    }
    return result;
}

// Java has one null string value. A present empty string stays distinct (R5).
package(flint.ai) NullableText normalizeText(NullableText value) pure nothrow @nogc
{
    return value.isNull || value.get() is null ? NullableText.init : value;
}

package(flint.ai) bool sameText(ref const NullableText left, ref const NullableText right)
{
    if (left.isNull)
        return right.isNull;
    return !right.isNull && left.get() == right.get();
}

package(flint.ai) int textHash(ref const NullableText value)
{
    return value.isNull ? 0 : stringHashCode(value.get());
}

package(flint.ai) string recordText(ref const NullableText value)
{
    return value.isNull ? "null" : value.get();
}

/// Legacy tool-call response data.
struct ToolResponse
{
    private NullableText id_;
    private NullableText name_;
    private NullableText responseData_;

    /// Creates a response from the call ID, name and optional response text.
    this(NullableText id, NullableText name, NullableText responseData) pure nothrow @nogc
    {
        id_ = normalizeText(id);
        name_ = normalizeText(name);
        responseData_ = normalizeText(responseData);
    }

    /// The identifier of the tool call this response answers.
    NullableText id() const pure nothrow @nogc
    {
        return id_;
    }

    /// The tool name.
    NullableText name() const pure nothrow @nogc
    {
        return name_;
    }

    /// The response text, when present.
    NullableText responseData() const pure nothrow @nogc
    {
        return responseData_;
    }

    /// Compares the record's three components.
    bool equals(const ToolResponse other) const
    {
        return sameText(id_, other.id_) && sameText(name_, other.name_) && sameText(responseData_, other.responseData_);
    }

    /// Hashes the three record components in Java order.
    int hashCode() const
    {
        return 31 * (31 * textHash(id_) + textHash(name_)) + textHash(responseData_);
    }

    /// Formats the three response components.
    string toString() const
    {
        string[7] parts = [
            "ToolResponse[id=", recordText(id_), ", name=", recordText(name_), ", responseData=",
            recordText(responseData_), "]"
        ];
        return joinRecord(parts[]);
    }

    mixin JavaObject;
}
