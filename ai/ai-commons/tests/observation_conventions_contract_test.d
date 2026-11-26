module observation_conventions_contract_test;

import flint.ai.observation.conventions : AiObservationAttributes, AiObservationMetricAttributes,
    AiObservationMetricNames, AiOperationType,
    AiProvider, AiTokenType,
    FlintAiKind, VectorStoreObservationAttributes, VectorStoreProvider, VectorStoreSimilarityMetric;
import flint.java.lang : IllegalArgumentException, NullPointerException;
import std.exception : assertThrown;

@safe:

@("observation enum values round-trip by name and retain declaration order")
unittest
{
    checkRoundTrip(AiObservationAttributes.values());
    checkRoundTrip(AiObservationMetricAttributes.values());
    checkRoundTrip(AiObservationMetricNames.values());
    checkRoundTrip(AiOperationType.values());
    checkRoundTrip(AiProvider.values());
    checkRoundTrip(AiTokenType.values());
    checkRoundTrip(FlintAiKind.values());
    checkRoundTrip(VectorStoreObservationAttributes.values());
    checkRoundTrip(VectorStoreProvider.values());
    checkRoundTrip(VectorStoreSimilarityMetric.values());

    auto values = AiTokenType.values();
    values[0] = AiTokenType.OUTPUT;
    assert(AiTokenType.values()[0] == AiTokenType.INPUT);
    assertThrown!IllegalArgumentException(AiTokenType.valueOf("input"));
    assertThrown!NullPointerException(AiTokenType.valueOf(null));
}

@("observation telemetry values stay distinct from enum names")
unittest
{
    assert(AiObservationAttributes.REQUEST_TOOL_NAMES.value() == "spring.ai.model.request.tool.names");
    assert(AiObservationMetricAttributes.TOKEN_TYPE.value() == "gen_ai.token.type");
    assert(AiObservationMetricNames.OPERATION_DURATION.value() == "gen_ai.client.operation.duration");
    assert(AiOperationType.EXECUTE_TOOL.value() == "execute_tool");
    assert(AiProvider.FLINT_AI.name() == "FLINT_AI");
    assert(AiProvider.FLINT_AI.value() == "spring_ai");
    assert(AiProvider.FLINT_AI.ordinal() == 9);
    assert(AiTokenType.OUTPUT.value() == "output");
    assert(FlintAiKind.CHAT_CLIENT.value() == "chat_client");
    assert(VectorStoreObservationAttributes.DB_SEARCH_SIMILARITY_METRIC.value() == "db.search.similarity_metric");
    assert(VectorStoreProvider.PG_VECTOR.value() == "pg_vector");
    assert(VectorStoreSimilarityMetric.COSINE.value() == "cosine");
}

private void checkRoundTrip(T)(T[] values)
{
    assert(values.length > 0);
    foreach (i, value; values)
    {
        assert(value.ordinal() == i);
        assert(T.valueOf(value.name()) == value);
        assert(value.toString() == value.name());
    }
}
