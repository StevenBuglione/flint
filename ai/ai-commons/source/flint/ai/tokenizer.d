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

// Ported from spring-ai v2.1.0, spring-ai-commons/src/main/java/org/springframework/ai/tokenizer/TokenCountEstimator.java
// Modified by the Flint authors.
module flint.ai.tokenizer;

import flint.ai.content : MediaContent;
import flint.java.lang : Iterable;
import std.typecons : Nullable;

@safe:

/// Estimates how many tokens a text or message uses.
interface TokenCountEstimator
{
    /// Estimates the token count of text, which may be absent (R5).
    int estimate(Nullable!string text);

    /// Estimates the token count of one message or document.
    int estimate(MediaContent content);

    /// Estimates the token count of the supplied messages.
    int estimate(Iterable!MediaContent messages);
}
