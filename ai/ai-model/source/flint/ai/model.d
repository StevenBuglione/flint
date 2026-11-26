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

// Ported from spring-ai v2.1.0, spring-ai-model/src/main/java/org/springframework/ai/model/{ApiKey,NoopApiKey,ResultMetadata,SimpleApiKey}.java
// Modified by the Flint authors.
module flint.ai.model;

import flint.java.lang : JavaObject, stringHashCode;

@safe:

/// Marker for metadata associated with the result of an AI model.
interface ResultMetadata
{
}

/// Supplies the current credential for a model request.
interface ApiKey
{
    /// Returns the current value. Call this per request so providers can rotate it.
    string getValue();
}

/// Indicates that a model request needs no API key.
class NoopApiKey : ApiKey
{
    /// Returns the empty credential used to omit the authorization header.
    override string getValue() pure nothrow @nogc
    {
        return "";
    }
}

/// Holds a static API key and redacts it from its string representation (R16).
final class SimpleApiKey : ApiKey
{
    private immutable(string) value_;

    /// Creates a key whose value is present. The empty string is allowed.
    this(string value)
    {
        import flint.java.lang : IllegalArgumentException;

        if (value is null)
            throw new IllegalArgumentException("API key value must not be null");
        value_ = value;
    }

    /// The stored credential.
    string value() const pure nothrow @nogc
    {
        return value_;
    }

    /// Returns the stored credential for a model request.
    override string getValue() pure nothrow @nogc
    {
        return value();
    }

    /// Compares the credential value with another SimpleApiKey.
    bool equals(Object other) pure nothrow @nogc
    {
        auto that = cast(SimpleApiKey) other;
        return that !is null && value_ == that.value_;
    }

    /// Computes the Java record hash of the credential.
    int hashCode() const pure nothrow @nogc
    {
        return stringHashCode(value_);
    }

    /// Returns the record name with its credential redacted.
    override string toString() pure nothrow @nogc
    {
        return "SimpleApiKey{value='***'}";
    }

    mixin JavaObject;
}
