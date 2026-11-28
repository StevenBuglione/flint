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

// Ported from spring-ai v2.1.0, spring-ai-model/src/test/java/org/springframework/ai/chat/prompt/ChatOptionsBuilderTests.java
// Modified by the Flint authors.
module chat_options_builder_tests;

import flint.ai.chat.prompt : ChatOptions, DefaultChatOptions;
import flint.java.lang : UnsupportedOperationException;
import flint.java.util : ArrayList, List;
import std.exception : collectException;
import std.typecons : Nullable;

@safe:

private alias ModelName = Nullable!string;
private alias Count = Nullable!int;
private alias Ratio = Nullable!double;
private alias StopSequences = List!string;

@("shouldBuildWithAllOptions")
unittest
{
    ChatOptions options = ChatOptions.builder().model(ModelName("gpt-4")).maxTokens(Count(100))
        .temperature(Ratio(0.7)).topP(Ratio(1.0)).topK(Count(40))
        .stopSequences(StopSequences.of("stop1", "stop2")).build();

    assert(options.getModel().get() == "gpt-4");
    assert(options.getMaxTokens().get() == 100);
    assert(options.getTemperature().get() == 0.7);
    assert(options.getTopP().get() == 1.0);
    assert(options.getTopK().get() == 40);
    assert(options.getStopSequences().size() == 2);
    assert(options.getStopSequences().get(0) == "stop1");
    assert(options.getStopSequences().get(1) == "stop2");
}

@("shouldBuildWithMinimalOptions")
unittest
{
    ChatOptions options = ChatOptions.builder().model(ModelName("gpt-4")).build();

    assert(options.getModel().get() == "gpt-4");
    assert(options.getMaxTokens().isNull);
    assert(options.getTemperature().isNull);
    assert(options.getTopP().isNull);
    assert(options.getTopK().isNull);
    assert(options.getStopSequences() is null);
}

@("shouldAllowBuilderReuse")
unittest
{
    auto builder = ChatOptions.builder();
    ChatOptions options1 = builder.model(ModelName("model1")).temperature(Ratio(0.7)).build();
    ChatOptions options2 = builder.model(ModelName("model2")).build();

    assert(options1.getModel().get() == "model1");
    assert(options1.getTemperature().get() == 0.7);
    assert(options2.getModel().get() == "model2");
    assert(options2.getTemperature().get() == 0.7);
}

@("shouldReturnSameBuilderInstanceOnEachMethod")
unittest
{
    auto builder = ChatOptions.builder();
    assert(builder.model(ModelName("test")) is builder);
}

@("shouldHaveExpectedDefaultValues")
unittest
{
    ChatOptions options = ChatOptions.builder().build();

    assert(options.getModel().isNull);
    assert(options.getTemperature().isNull);
    assert(options.getMaxTokens().isNull);
    assert(options.getTopP().isNull);
    assert(options.getTopK().isNull);
    assert(options.getFrequencyPenalty().isNull);
    assert(options.getPresencePenalty().isNull);
    assert(options.getStopSequences() is null);
}

@("shouldBeImmutableAfterBuild")
unittest
{
    auto stops = new ArrayList!string();
    stops.add("stop1");
    stops.add("stop2");
    ChatOptions options = ChatOptions.builder().stopSequences(stops).build();

    assert(collectException!UnsupportedOperationException(options.getStopSequences().add("stop3")) !is null);
}

@("shouldHandleNullStopSequences")
unittest
{
    ChatOptions options = ChatOptions.builder().model(ModelName("test-model")).stopSequences(null).build();
    assert(options.getStopSequences() is null);
}

@("shouldHandleEmptyStopSequences")
unittest
{
    ChatOptions options = ChatOptions.builder().model(ModelName("test-model"))
        .stopSequences(StopSequences.of()).build();
    assert(options.getStopSequences() !is null && options.getStopSequences().isEmpty());
}

@("shouldHandleFrequencyAndPresencePenalties")
unittest
{
    ChatOptions options = ChatOptions.builder().model(ModelName("test-model"))
        .frequencyPenalty(Ratio(0.5)).presencePenalty(Ratio(0.3)).build();

    assert(options.getFrequencyPenalty().get() == 0.5);
    assert(options.getPresencePenalty().get() == 0.3);
}

@("shouldMaintainStopSequencesOrder")
unittest
{
    ChatOptions options = ChatOptions.builder().model(ModelName("test-model"))
        .stopSequences(StopSequences.of("first", "second", "third", "fourth")).build();

    auto stops = options.getStopSequences();
    assert(stops.size() == 4);
    assert(stops.get(0) == "first" && stops.get(1) == "second" && stops.get(2) == "third" && stops.get(3) == "fourth");
}

@("shouldHandleSpecialStringValues")
unittest
{
    ChatOptions options = ChatOptions.builder().model(ModelName(""))
        .stopSequences(StopSequences.of("", "  ", "\n", "\t")).build();

    assert(options.getModel().get().length == 0);
    auto stops = options.getStopSequences();
    assert(stops.size() == 4);
    assert(stops.get(0) == "" && stops.get(1) == "  " && stops.get(2) == "\n" && stops.get(3) == "\t");
}

@("mutate copies the snapshot into a new builder")
unittest
{
    ChatOptions original = ChatOptions.builder().model(ModelName("gpt-4")).temperature(Ratio(0.7))
        .stopSequences(StopSequences.of("stop1")).build();

    ChatOptions mutated = original.mutate().maxTokens(Count(100)).build();

    assert(original.getMaxTokens().isNull);
    assert(mutated.getMaxTokens().get() == 100);
    assert(mutated.getModel().get() == "gpt-4");
    assert(mutated.getTemperature().get() == 0.7);
    assert(mutated.getStopSequences().size() == 1 && mutated.getStopSequences().get(0) == "stop1");
}

@("clone copies every setting and leaves the original independent")
unittest
{
    auto builder = ChatOptions.builder().model(ModelName("gpt-4")).maxTokens(Count(100))
        .temperature(Ratio(0.7)).stopSequences(StopSequences.of("stop1"));

    auto copy = builder.clone();
    copy.model(ModelName("gpt-5")).maxTokens(Count(200)).stopSequences(StopSequences.of("stop2"));

    ChatOptions original = builder.build();
    ChatOptions cloned = copy.build();
    assert(original.getModel().get() == "gpt-4");
    assert(original.getMaxTokens().get() == 100);
    assert(original.getTemperature().get() == 0.7);
    assert(original.getStopSequences().size() == 1 && original.getStopSequences().get(0) == "stop1");
    assert(cloned.getModel().get() == "gpt-5");
    assert(cloned.getMaxTokens().get() == 200);
    assert(cloned.getTemperature().get() == 0.7);
    assert(cloned.getStopSequences().size() == 1 && cloned.getStopSequences().get(0) == "stop2");
}

@("combineWith keeps this builder's values and appends the other's stop sequences")
unittest
{
    auto builder = ChatOptions.builder().model(ModelName("gpt-4")).temperature(Ratio(0.7))
        .stopSequences(StopSequences.of("left"));
    auto other = ChatOptions.builder().model(ModelName("gpt-5")).maxTokens(Count(100))
        .stopSequences(StopSequences.of("right"));

    assert(builder.combineWith(other) is builder);
    ChatOptions combined = builder.build();
    assert(combined.getModel().get() == "gpt-5");
    assert(combined.getTemperature().get() == 0.7);
    assert(combined.getMaxTokens().get() == 100);
    assert(combined.getStopSequences().size() == 2);
    assert(combined.getStopSequences().get(0) == "left");
    assert(combined.getStopSequences().get(1) == "right");
}

@("combineWith copies stop sequences when this builder has none")
unittest
{
    auto builder = ChatOptions.builder().model(ModelName("gpt-4"));
    auto other = ChatOptions.builder().stopSequences(StopSequences.of("only"));

    builder.combineWith(other);
    ChatOptions combined = builder.build();
    assert(combined.getModel().get() == "gpt-4");
    assert(combined.getStopSequences().size() == 1 && combined.getStopSequences().get(0) == "only");
}
