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

import flint.ai.chat.prompt : ChatOptions, DefaultChatOptions;
import flint.ai.model : ModelOptions;
import flint.java.lang : NullPointerException, UnsupportedOperationException;
import flint.java.util : ArrayList, List;
import std.exception : collectException;
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

private class SnapshotOptions : DefaultChatOptions
{
    this(StopSequences stops)
    {
        super(ModelName(""), Ratio.init, Count(128), Ratio(-0.5), stops, Ratio(0.0), Count(0), Ratio(0.875));
    }

    this(StopSequences stops, Ratio frequency, Ratio temperature = Ratio(0.0),
            ModelName model = ModelName("m😀"), Count maxTokens = Count(128),
            Ratio presence = Ratio(-0.5), Count topK = Count(0), Ratio topP = Ratio(0.875))
    {
        super(model, frequency, maxTokens, presence, stops, temperature, topK, topP);
    }
}

@("default options preserve settings and snapshot stop sequences in order")
unittest
{
    auto stops = new ArrayList!string();
    stops.add("β");
    stops.add("end");
    stops.add("β");
    stops.add("");

    ChatOptions options = new SnapshotOptions(stops);
    assert(!options.getModel().isNull && options.getModel().get().length == 0);
    assert(options.getFrequencyPenalty().isNull);
    assert(options.getMaxTokens().get() == 128);
    assert(options.getPresencePenalty().get() == -0.5);
    assert(options.getTemperature().get() == 0.0);
    assert(options.getTopK().get() == 0);
    assert(options.getTopP().get() == 0.875);

    stops.set(0, "changed");
    stops.add("new");
    auto snapshot = options.getStopSequences();
    assert(snapshot.size() == 4);
    assert(snapshot.get(0) == "β" && snapshot.get(1) == "end" && snapshot.get(2) == "β");
    assert(snapshot.get(3) !is null && snapshot.get(3).length == 0);
    assert(collectException!UnsupportedOperationException(snapshot.add("invalid")) !is null);
}

@("default options distinguish absent and present empty stop lists")
unittest
{
    assert((new SnapshotOptions(null)).getStopSequences() is null);
    auto empty = (new SnapshotOptions(StopSequences.of())).getStopSequences();
    assert(empty !is null && empty.isEmpty());
}

@("default options reject a null stop element")
unittest
{
    auto stops = new ArrayList!string();
    stops.add("");
    stops.add(null);
    assert(collectException!NullPointerException(new SnapshotOptions(stops)) !is null);
}

@("default options use Java equality for all stored fields")
unittest
{
    auto stops = StopSequences.of("β", "");
    auto frequency = Ratio(double.nan);
    auto temperature = Ratio(0.0);
    auto model = ModelName("m😀");
    auto maxTokens = Count(128);
    auto presence = Ratio(-0.5);
    auto topK = Count(0);
    auto left = new SnapshotOptions(stops, frequency);
    auto equal = new SnapshotOptions(StopSequences.of("β", ""), Ratio(-double.nan));
    assert(left.equals(equal) && equal.equals(left) && left == equal);
    assert(left.hashCode() == -1_268_627_134 && left.hashCode() == equal.hashCode());
    assert(!left.equals(null) && !left.equals(new Object()));
    assert(!left.equals(new SnapshotOptions(StopSequences.of("", "β"), frequency)));
    assert(!left.equals(new SnapshotOptions(stops, Ratio.init)));
    assert(!left.equals(new SnapshotOptions(stops, frequency, Ratio(-0.0))));
    assert(!left.equals(new SnapshotOptions(stops, frequency, temperature, ModelName.init)));
    assert(!left.equals(new SnapshotOptions(stops, frequency, temperature, model, Count(127))));
    assert(!left.equals(new SnapshotOptions(stops, frequency, temperature, model, maxTokens, Ratio.init)));
    assert(!left.equals(new SnapshotOptions(stops, frequency, temperature, model, maxTokens, presence, Count.init)));
    auto absentTopP = new SnapshotOptions(stops, frequency, temperature, model, maxTokens, presence, topK, Ratio.init);
    assert(!left.equals(absentTopP));
}

@("default options distinguish absent stops and check the runtime class")
unittest
{
    static final class DerivedOptions : SnapshotOptions
    {
        this()
        {
            super(null, Ratio(double.nan));
        }
    }

    auto absent = new SnapshotOptions(null, Ratio(double.nan));
    auto empty = new SnapshotOptions(StopSequences.of(), Ratio(double.nan));
    auto derived = new DerivedOptions();
    assert(!absent.equals(empty));
    assert(absent.hashCode() == 2_124_060_145 && empty.hashCode() == 2_124_089_936);
    assert(!absent.equals(derived) && !derived.equals(absent));
    assert(derived.equals(new DerivedOptions()) && derived.hashCode() == absent.hashCode());
}
