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

// Ported from spring-ai v2.1.0, spring-ai-model/src/test/java/org/springframework/ai/chat/metadata/DefaultUsageTests.java
// Modified by the Flint authors.
module default_usage_tests;

import flint.ai.chat.metadata : DefaultUsage, Usage;
import flint.engine.aot.any : Any;
import flint.java.util : Map;
import std.typecons : Nullable, nullable;

@safe:

private alias Count = Nullable!int;
private alias NativeMap = Map!(string, Any);

@("testCalculatedTotalTokens")
unittest
{
    Usage computed = new DefaultUsage(nullable(100), nullable(50), Count.init);
    assert(computed.getTotalTokens() == 150);

    Usage explicit = new DefaultUsage(nullable(100), nullable(50), nullable(200));
    assert(explicit.getTotalTokens() == 200);
}

@("testCacheFields")
unittest
{
    Usage usage = new DefaultUsage(nullable(100), nullable(50), nullable(150), Any.init,
            nullable(500L), nullable(200L));
    assert(usage.getCacheReadInputTokens().get() == 500L);
    assert(usage.getCacheWriteInputTokens().get() == 200L);
}

@("testCacheFieldsNullByDefault")
unittest
{
    Usage usage = new DefaultUsage(nullable(100), nullable(50), nullable(150));
    assert(usage.getCacheReadInputTokens().isNull);
    assert(usage.getCacheWriteInputTokens().isNull);
}

@("testToString")
unittest
{
    enum expected = "DefaultUsage{promptTokens=100, completionTokens=50, totalTokens=150}";
    assert(new DefaultUsage(nullable(100), nullable(50), nullable(150)).toString() == expected);

    auto nativeUsage = Any.of(NativeMap.of("custom", Any.of("value")));
    assert(new DefaultUsage(nullable(100), nullable(50), nullable(150), nativeUsage).toString() == expected);

    assert(new DefaultUsage(Count.init, Count.init, Count.init)
            .toString() == "DefaultUsage{promptTokens=0, completionTokens=0, totalTokens=0}");
}

@("testToStringWithCacheFields")
unittest
{
    auto usage = new DefaultUsage(nullable(100), nullable(50), nullable(150), Any.init,
            nullable(500L), nullable(200L));
    assert(usage.toString() == "DefaultUsage{promptTokens=100, completionTokens=50, totalTokens=150, "
            ~ "cacheReadInputTokens=500, cacheWriteInputTokens=200}");
}

@("testEqualsAndHashCode")
unittest
{
    auto first = new DefaultUsage(nullable(100), nullable(50), nullable(150));
    auto same = new DefaultUsage(nullable(100), nullable(50), nullable(150));
    auto different = new DefaultUsage(nullable(200), nullable(100), nullable(300));
    auto nativeUsage = new DefaultUsage(nullable(100), nullable(50), nullable(150),
            Any.of(NativeMap.of("custom", Any.of("value"))));

    assert(first == same && first.hashCode() == same.hashCode());
    assert(first != different && first.hashCode() != different.hashCode());
    assert(first != nativeUsage && first.hashCode() != nativeUsage.hashCode());
    assert(!first.equals(null) && !first.equals(new Object()));
    assert(first.equals(first));
    assert(first.equals(same) == same.equals(first));

    auto left = NativeMap.of("key", Any.of("value"));
    auto right = NativeMap.of("key", Any.of("value"));
    auto firstMap = new DefaultUsage(nullable(100), nullable(50), nullable(150), Any.of(left));
    auto secondMap = new DefaultUsage(nullable(100), nullable(50), nullable(150), Any.of(right));
    assert(left !is right);
    assert(firstMap == secondMap && firstMap.hashCode() == secondMap.hashCode());
}

@("default usage preserves absent native data and distinguishes absent cache counts from zero")
unittest
{
    auto usage = new DefaultUsage(Count.init, nullable(3));
    assert(usage.getPromptTokens().get() == 0);
    assert(usage.getCompletionTokens().get() == 3);
    assert(usage.getTotalTokens() == 3);
    assert(usage.getNativeUsage().isNull());

    auto withCache = new DefaultUsage(Count.init, nullable(3), Count.init, Any.init,
            nullable(0L), Nullable!long.init);
    assert(withCache.getCacheReadInputTokens().get() == 0L);
    assert(usage != withCache);
}

@("default usage equality requires the same concrete class")
unittest
{
    auto base = new DefaultUsage(nullable(1), nullable(2));
    auto derived = new DerivedUsage();
    assert(!base.equals(derived));
    assert(!derived.equals(base));
    assert(derived.equals(new DerivedUsage()));
}

private final class DerivedUsage : DefaultUsage
{
    this()
    {
        super(nullable(1), nullable(2));
    }
}
