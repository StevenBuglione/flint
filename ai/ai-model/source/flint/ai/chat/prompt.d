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

// Ported from spring-ai v2.1.0, spring-ai-model/src/main/java/org/springframework/ai/chat/prompt/ChatOptions.java
// Modified by the Flint authors.
module flint.ai.chat.prompt;

import flint.ai.model : ModelOptions;
import flint.java.util : List;
import std.typecons : Nullable;

@safe:

private alias ModelName = Nullable!string;
private alias Count = Nullable!int;
private alias Ratio = Nullable!double;
private alias StopSequences = List!string;

/// Options that can be shared across chat model providers.
interface ChatOptions : ModelOptions
{
    /// Returns the model name, when specified.
    ModelName getModel();

    /// Returns the frequency penalty, when specified.
    Ratio getFrequencyPenalty();

    /// Returns the maximum number of tokens, when specified.
    Count getMaxTokens();

    /// Returns the presence penalty, when specified.
    Ratio getPresencePenalty();

    /// Returns the stop sequences, or null when unspecified.
    StopSequences getStopSequences();

    /// Returns the temperature, when specified.
    Ratio getTemperature();

    /// Returns the top K, when specified.
    Count getTopK();

    /// Returns the top P, when specified.
    Ratio getTopP();
}
