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

module chat_options_contract_tests;

import flint.ai.chat.prompt : ChatOptions;
import flint.ai.model : ModelOptions;
import flint.java.util : List;
import std.typecons : Nullable;

@safe:

private alias ModelName = Nullable!string;
private alias Count = Nullable!int;
private alias Ratio = Nullable!double;
private alias StopSequences = List!string;

private final class FixtureOptions : ChatOptions
{
    private StopSequences stops_;

    this(StopSequences stops)
    {
        stops_ = stops;
    }

    override ModelName getModel()
    {
        return ModelName("");
    }

    override Ratio getFrequencyPenalty()
    {
        return Ratio.init;
    }

    override Count getMaxTokens()
    {
        return Count.init;
    }

    override Ratio getPresencePenalty()
    {
        return Ratio(0.0);
    }

    override StopSequences getStopSequences()
    {
        return stops_;
    }

    override Ratio getTemperature()
    {
        return Ratio(0.25);
    }

    override Count getTopK()
    {
        return Count(0);
    }

    override Ratio getTopP()
    {
        return Ratio(0.875);
    }
}

@("chat option getters keep missing values distinct from configured zero and empty values")
unittest
{
    ModelOptions options = new FixtureOptions(null);
    auto chat = cast(ChatOptions) options;
    assert(chat !is null);
    assert(!chat.getModel().isNull && chat.getModel().get().length == 0);
    assert(chat.getFrequencyPenalty().isNull);
    assert(chat.getMaxTokens().isNull);
    assert(!chat.getPresencePenalty().isNull && chat.getPresencePenalty().get() == 0.0);
    assert(chat.getStopSequences() is null);
    assert(chat.getTemperature().get() == 0.25);
    assert(!chat.getTopK().isNull && chat.getTopK().get() == 0);
    assert(chat.getTopP().get() == 0.875);

    auto empty = StopSequences.of();
    chat = new FixtureOptions(empty);
    assert(chat.getStopSequences() is empty && chat.getStopSequences().isEmpty());
}
