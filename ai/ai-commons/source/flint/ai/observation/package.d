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

// Ported from spring-ai v2.1.0, spring-ai-commons/src/main/java/org/springframework/ai/observation/{AiOperationMetadata,ObservabilityHelper}.java
// Modified by the Flint authors.
module flint.ai.observation;

import flint.engine.aot.any : Any;
import flint.java.lang : NullPointerException, stringHashCode;
import flint.java.util : List, Map;
import flint.util : Assert;

@safe:

/// Metadata associated with a model operation and its provider.
struct AiOperationMetadata
{
    private string operationType_;
    private string provider_;

    @disable this();

    /// Creates metadata after checking both required fields for text.
    this(string operationType, string provider)
    {
        Assert.hasText(operationType, "operationType cannot be null or empty");
        Assert.hasText(provider, "provider cannot be null or empty");
        operationType_ = operationType;
        provider_ = provider;
    }

    /// The operation performed by the model.
    string operationType() const pure nothrow @nogc
    {
        return operationType_;
    }

    /// The name of the service providing the model.
    string provider() const pure nothrow @nogc
    {
        return provider_;
    }

    /// Compares both record components by value.
    bool equals(const AiOperationMetadata other) const pure nothrow @nogc
    {
        return operationType_ == other.operationType_ && provider_ == other.provider_;
    }

    /// Implements D equality with the same component comparisons.
    bool opEquals(const AiOperationMetadata other) const pure nothrow @nogc
    {
        return equals(other);
    }

    /// Returns the Java record hash in component order.
    int hashCode() const pure nothrow @nogc
    {
        return 31 * stringHashCode(operationType_) + stringHashCode(provider_);
    }

    /// Returns the value's hash for D collections.
    size_t toHash() const pure nothrow @nogc
    {
        return cast(uint) hashCode();
    }

    /// Returns the Java record text with both components.
    string toString() const pure nothrow
    {
        return "AiOperationMetadata[operationType=" ~ operationType_ ~ ", provider=" ~ provider_ ~ "]";
    }

    /// Creates an empty builder.
    static Builder builder() pure nothrow @nogc
    {
        return Builder.init;
    }

    /// Collects the operation and provider before validating them.
    static struct Builder
    {
        private string operationType_;
        private string provider_;

        /// Sets the operation performed by the model.
        ref Builder operationType(string operationType) return pure nothrow @nogc
        {
            operationType_ = operationType;
            return this;
        }

        /// Sets the name of the service providing the model.
        ref Builder provider(string provider) return pure nothrow @nogc
        {
            provider_ = provider;
            return this;
        }

        /// Validates the current fields and returns their value.
        AiOperationMetadata build() const
        {
            return AiOperationMetadata(operationType_, provider_);
        }
    }
}

/// Formats collections for observation attributes.
final class ObservabilityHelper
{
    @disable this();

    /// Quotes each key and value in the supplied map's iteration order.
    static string concatenateEntries(Map!(string, Any) keyValues)
    {
        if (keyValues is null)
            throw new NullPointerException();

        string result = "[";
        keyValues.forEach((string key, Any value) {
            if (result.length > 1)
                result ~= ", ";
            result ~= '"';
            result ~= key is null ? "null" : key;
            result ~= `":"`;
            result ~= observationValueText(value);
            result ~= '"';
        });
        result ~= ']';
        return result;
    }

    /// Quotes each element in list order, preserving its text verbatim.
    static string concatenateStrings(List!string strings)
    {
        if (strings is null)
            throw new NullPointerException();

        string result = "[";
        strings.forEach((string value) {
            if (result.length > 1)
                result ~= ", ";
            result ~= '"';
            result ~= value is null ? "null" : value;
            result ~= '"';
        });
        result ~= ']';
        return result;
    }
}

private string observationValueText(Any value)
{
    import flint.engine.aot.objects : objectToString;
    import flint.java.lang : doubleToString, floatToString;

    if (value.isNull)
        return "null";
    if (auto object = value.asObject())
    {
        const text = objectToString(object);
        return text is null ? "null" : text;
    }

    switch (value.typeName)
    {
    case "double":
        return doubleToString(value.get!double);
    case "float":
        return floatToString(cast(float) value.get!double);
    default:
        return value.toString();
    }
}
