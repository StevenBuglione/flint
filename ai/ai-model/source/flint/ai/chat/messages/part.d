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

// Ported from spring-ai v2.1.0, spring-ai-model/src/main/java/org/springframework/ai/chat/messages/part/OpaquePayload.java
// Modified by the Flint authors.
module flint.ai.chat.messages.part;

import flint.util : Assert;

@safe:

/// Provider-owned data that a message part can carry back to its origin unchanged.
struct OpaquePayload
{
    private string provider_;
    private string kind_;
    private string data_;

    @disable this();

    /// Creates a payload from nonblank provider and kind names and a present data string.
    this(string provider, string kind, string data)
    {
        Assert.hasText(provider, "provider must not be empty");
        Assert.hasText(kind, "kind must not be empty");
        Assert.notNull(data, "data must not be null");
        this.provider_ = provider;
        this.kind_ = kind;
        this.data_ = data;
    }

    /// The provider that produced the payload.
    string provider() const pure nothrow @nogc
    {
        return provider_;
    }

    /// The provider's name for this kind of payload.
    string kind() const pure nothrow @nogc
    {
        return kind_;
    }

    /// The payload string exactly as supplied by the provider adapter.
    string data() const pure nothrow @nogc
    {
        return data_;
    }
}
