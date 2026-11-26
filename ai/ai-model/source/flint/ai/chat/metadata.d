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

// Ported from spring-ai v2.1.0, spring-ai-model/src/main/java/org/springframework/ai/chat/metadata/{RateLimit,EmptyRateLimit}.java
// Modified by the Flint authors.
module flint.ai.chat.metadata;

import flint.java.time : Duration;
import std.typecons : Nullable;

@safe:

private alias LimitCount = Nullable!long;
private alias ResetTime = Nullable!Duration;

/// A provider's request and token rate limits, balance, and time until reset.
/// A provider may omit a measurement. An empty Nullable represents an omitted value (R5).
interface RateLimit
{
    /// Maximum number of requests allowed by the current limit.
    LimitCount getRequestsLimit();

    /// Requests remaining before the limit is exhausted.
    LimitCount getRequestsRemaining();

    /// Time until the request limit resets.
    ResetTime getRequestsReset();

    /// Maximum number of tokens allowed by the current limit.
    LimitCount getTokensLimit();

    /// Tokens remaining before the limit is exhausted.
    LimitCount getTokensRemaining();

    /// Time until the token limit resets.
    ResetTime getTokensReset();
}

/// A RateLimit with present zero values for every property.
class EmptyRateLimit : RateLimit
{
    /// Creates a zero-valued rate limit.
    this() pure nothrow @nogc
    {
    }

    override LimitCount getRequestsLimit() pure nothrow @nogc
    {
        return LimitCount(0);
    }

    override LimitCount getRequestsRemaining() pure nothrow @nogc
    {
        return LimitCount(0);
    }

    override ResetTime getRequestsReset() pure nothrow @nogc
    {
        return ResetTime(Duration.ZERO);
    }

    override LimitCount getTokensLimit() pure nothrow @nogc
    {
        return LimitCount(0);
    }

    override LimitCount getTokensRemaining() pure nothrow @nogc
    {
        return LimitCount(0);
    }

    override ResetTime getTokensReset() pure nothrow @nogc
    {
        return ResetTime(Duration.ZERO);
    }
}
