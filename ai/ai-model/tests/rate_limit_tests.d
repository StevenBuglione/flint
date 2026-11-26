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

module rate_limit_tests;

import flint.ai.chat.metadata : EmptyRateLimit, RateLimit;
import flint.java.time : Duration;
import std.typecons : Nullable;

@safe:

@("empty rate limits expose zero through the interface and retain identity")
unittest
{
    RateLimit empty = new EmptyRateLimit();
    assert(empty.getRequestsLimit().get() == 0);
    assert(empty.getRequestsRemaining().get() == 0);
    assert(empty.getRequestsReset().get() == Duration.ZERO);
    assert(empty.getTokensLimit().get() == 0);
    assert(empty.getTokensRemaining().get() == 0);
    assert(empty.getTokensReset().get() == Duration.ZERO);

    auto other = new EmptyRateLimit();
    assert(empty !is other);
}

@("provider rate limits distinguish missing values from zero and preserve the full count")
unittest
{
    RateLimit provider = new class RateLimit
    {
        override Nullable!long getRequestsLimit()
        {
            return Nullable!long(long.max);
        }

        override Nullable!long getRequestsRemaining()
        {
            return Nullable!long.init;
        }

        override Nullable!Duration getRequestsReset()
        {
            return Nullable!Duration.init;
        }

        override Nullable!long getTokensLimit()
        {
            return Nullable!long(0);
        }

        override Nullable!long getTokensRemaining()
        {
            return Nullable!long(0);
        }

        override Nullable!Duration getTokensReset()
        {
            return Nullable!Duration(Duration.ofNanos(1));
        }
    };

    assert(provider.getRequestsLimit().get() == long.max);
    assert(provider.getRequestsRemaining().isNull);
    assert(provider.getRequestsReset().isNull);
    assert(provider.getTokensLimit().get() == 0);
    assert(provider.getTokensReset().get() == Duration.ofNanos(1));
}
