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

// Ported from spring-ai v2.1.0, spring-ai-commons/src/main/java/org/springframework/ai/observation/conventions/{AiObservationAttributes,AiObservationMetricAttributes,AiObservationMetricNames,AiOperationType,AiProvider,AiTokenType,SpringAiKind,VectorStoreObservationAttributes,VectorStoreProvider,VectorStoreSimilarityMetric}.java
// Modified by the Flint authors.
module flint.ai.observation.conventions;

@safe:

private struct ConventionEntry
{
    string name;
    string value;
}

private int conventionOrdinal(string name, scope const(ConventionEntry)[] entries, string typeName)
{
    import flint.java.lang : IllegalArgumentException, NullPointerException;

    if (name is null)
        throw new NullPointerException("Name is null");
    foreach (i, ref entry; entries)
        if (entry.name == name)
            return cast(int) i;
    throw new IllegalArgumentException("No enum constant " ~ typeName ~ "." ~ name);
}

/// Attribute keys used in AI observations.
struct AiObservationAttributes
{
    /// Telemetry value `gen_ai.operation.name`.
    static immutable AiObservationAttributes AI_OPERATION_TYPE = AiObservationAttributes(0);

    /// Telemetry value `gen_ai.system`.
    static immutable AiObservationAttributes AI_PROVIDER = AiObservationAttributes(1);

    /// Telemetry value `gen_ai.request.model`.
    static immutable AiObservationAttributes REQUEST_MODEL = AiObservationAttributes(2);

    /// Telemetry value `gen_ai.request.frequency_penalty`.
    static immutable AiObservationAttributes REQUEST_FREQUENCY_PENALTY = AiObservationAttributes(3);

    /// Telemetry value `gen_ai.request.max_tokens`.
    static immutable AiObservationAttributes REQUEST_MAX_TOKENS = AiObservationAttributes(4);

    /// Telemetry value `gen_ai.request.presence_penalty`.
    static immutable AiObservationAttributes REQUEST_PRESENCE_PENALTY = AiObservationAttributes(5);

    /// Telemetry value `gen_ai.request.stop_sequences`.
    static immutable AiObservationAttributes REQUEST_STOP_SEQUENCES = AiObservationAttributes(6);

    /// Telemetry value `gen_ai.request.stream`.
    static immutable AiObservationAttributes REQUEST_STREAM = AiObservationAttributes(7);

    /// Telemetry value `gen_ai.request.temperature`.
    static immutable AiObservationAttributes REQUEST_TEMPERATURE = AiObservationAttributes(8);

    /// Telemetry value `spring.ai.model.request.tool.names`.
    static immutable AiObservationAttributes REQUEST_TOOL_NAMES = AiObservationAttributes(9);

    /// Telemetry value `gen_ai.request.top_k`.
    static immutable AiObservationAttributes REQUEST_TOP_K = AiObservationAttributes(10);

    /// Telemetry value `gen_ai.request.top_p`.
    static immutable AiObservationAttributes REQUEST_TOP_P = AiObservationAttributes(11);

    /// Telemetry value `gen_ai.request.embedding.dimensions`.
    static immutable AiObservationAttributes REQUEST_EMBEDDING_DIMENSIONS = AiObservationAttributes(12);

    /// Telemetry value `gen_ai.request.image.response_format`.
    static immutable AiObservationAttributes REQUEST_IMAGE_RESPONSE_FORMAT = AiObservationAttributes(13);

    /// Telemetry value `gen_ai.request.image.size`.
    static immutable AiObservationAttributes REQUEST_IMAGE_SIZE = AiObservationAttributes(14);

    /// Telemetry value `gen_ai.request.image.style`.
    static immutable AiObservationAttributes REQUEST_IMAGE_STYLE = AiObservationAttributes(15);

    /// Telemetry value `gen_ai.request.audio.voice`.
    static immutable AiObservationAttributes REQUEST_AUDIO_VOICE = AiObservationAttributes(16);

    /// Telemetry value `gen_ai.request.audio.response_format`.
    static immutable AiObservationAttributes REQUEST_AUDIO_RESPONSE_FORMAT = AiObservationAttributes(17);

    /// Telemetry value `gen_ai.request.audio.speed`.
    static immutable AiObservationAttributes REQUEST_AUDIO_SPEED = AiObservationAttributes(18);

    /// Telemetry value `gen_ai.response.finish_reasons`.
    static immutable AiObservationAttributes RESPONSE_FINISH_REASONS = AiObservationAttributes(19);

    /// Telemetry value `gen_ai.response.id`.
    static immutable AiObservationAttributes RESPONSE_ID = AiObservationAttributes(20);

    /// Telemetry value `gen_ai.response.model`.
    static immutable AiObservationAttributes RESPONSE_MODEL = AiObservationAttributes(21);

    /// Telemetry value `gen_ai.usage.cache_creation.input_tokens`.
    static immutable AiObservationAttributes USAGE_CACHE_WRITE_INPUT_TOKENS = AiObservationAttributes(22);

    /// Telemetry value `gen_ai.usage.cache_read.input_tokens`.
    static immutable AiObservationAttributes USAGE_CACHE_READ_INPUT_TOKENS = AiObservationAttributes(23);

    /// Telemetry value `gen_ai.usage.input_tokens`.
    static immutable AiObservationAttributes USAGE_INPUT_TOKENS = AiObservationAttributes(24);

    /// Telemetry value `gen_ai.usage.output_tokens`.
    static immutable AiObservationAttributes USAGE_OUTPUT_TOKENS = AiObservationAttributes(25);

    /// Telemetry value `gen_ai.usage.total_tokens`.
    static immutable AiObservationAttributes USAGE_TOTAL_TOKENS = AiObservationAttributes(26);

    private static immutable ConventionEntry[27] entries = [
        ConventionEntry("AI_OPERATION_TYPE", "gen_ai.operation.name"),
        ConventionEntry("AI_PROVIDER", "gen_ai.system"),
        ConventionEntry("REQUEST_MODEL", "gen_ai.request.model"),
        ConventionEntry("REQUEST_FREQUENCY_PENALTY", "gen_ai.request.frequency_penalty"),
        ConventionEntry("REQUEST_MAX_TOKENS", "gen_ai.request.max_tokens"),
        ConventionEntry("REQUEST_PRESENCE_PENALTY", "gen_ai.request.presence_penalty"),
        ConventionEntry("REQUEST_STOP_SEQUENCES", "gen_ai.request.stop_sequences"),
        ConventionEntry("REQUEST_STREAM", "gen_ai.request.stream"),
        ConventionEntry("REQUEST_TEMPERATURE", "gen_ai.request.temperature"),
        ConventionEntry("REQUEST_TOOL_NAMES", "spring.ai.model.request.tool.names"),
        ConventionEntry("REQUEST_TOP_K", "gen_ai.request.top_k"),
        ConventionEntry("REQUEST_TOP_P", "gen_ai.request.top_p"),
        ConventionEntry("REQUEST_EMBEDDING_DIMENSIONS", "gen_ai.request.embedding.dimensions"),
        ConventionEntry("REQUEST_IMAGE_RESPONSE_FORMAT", "gen_ai.request.image.response_format"),
        ConventionEntry("REQUEST_IMAGE_SIZE", "gen_ai.request.image.size"),
        ConventionEntry("REQUEST_IMAGE_STYLE", "gen_ai.request.image.style"),
        ConventionEntry("REQUEST_AUDIO_VOICE", "gen_ai.request.audio.voice"),
        ConventionEntry("REQUEST_AUDIO_RESPONSE_FORMAT", "gen_ai.request.audio.response_format"),
        ConventionEntry("REQUEST_AUDIO_SPEED", "gen_ai.request.audio.speed"),
        ConventionEntry("RESPONSE_FINISH_REASONS", "gen_ai.response.finish_reasons"),
        ConventionEntry("RESPONSE_ID", "gen_ai.response.id"),
        ConventionEntry("RESPONSE_MODEL", "gen_ai.response.model"),
        ConventionEntry("USAGE_CACHE_WRITE_INPUT_TOKENS",
                "gen_ai.usage.cache_creation.input_tokens"),
        ConventionEntry("USAGE_CACHE_READ_INPUT_TOKENS",
                "gen_ai.usage.cache_read.input_tokens"),
        ConventionEntry("USAGE_INPUT_TOKENS", "gen_ai.usage.input_tokens"),
        ConventionEntry("USAGE_OUTPUT_TOKENS", "gen_ai.usage.output_tokens"),
        ConventionEntry("USAGE_TOTAL_TOKENS", "gen_ai.usage.total_tokens"),
    ];

    private int ordinal_;

    private this(int ordinal) pure nothrow @nogc
    {
        ordinal_ = ordinal;
    }

    /// Returns the enum constant's name.
    string name() const pure nothrow @nogc
    {
        return entries[ordinal_].name;
    }

    /// Returns the enum constant's zero-based declaration index.
    int ordinal() const pure nothrow @nogc
    {
        return ordinal_;
    }

    /// Returns the constant's telemetry value.
    string value() const pure nothrow @nogc
    {
        return entries[ordinal_].value;
    }

    /// Returns a fresh array of constants in declaration order.
    static AiObservationAttributes[] values() pure nothrow
    {
        auto values = new AiObservationAttributes[entries.length];
        foreach (i, ref value; values)
            value = AiObservationAttributes(cast(int) i);
        return values;
    }

    /// Looks up a constant by its exact name.
    static AiObservationAttributes valueOf(string name)
    {
        return AiObservationAttributes(conventionOrdinal(name, entries,
                "flint.ai.observation.conventions.AiObservationAttributes"));
    }

    /// Returns the enum constant's name.
    string toString() const pure nothrow @nogc
    {
        return name();
    }
}

/// Attribute keys for metrics about AI operations.
struct AiObservationMetricAttributes
{
    /// Telemetry value `gen_ai.token.type`.
    static immutable AiObservationMetricAttributes TOKEN_TYPE = AiObservationMetricAttributes(0);

    private static immutable ConventionEntry[1] entries = [
        ConventionEntry("TOKEN_TYPE", "gen_ai.token.type"),
    ];

    private int ordinal_;

    private this(int ordinal) pure nothrow @nogc
    {
        ordinal_ = ordinal;
    }

    /// Returns the enum constant's name.
    string name() const pure nothrow @nogc
    {
        return entries[ordinal_].name;
    }

    /// Returns the enum constant's zero-based declaration index.
    int ordinal() const pure nothrow @nogc
    {
        return ordinal_;
    }

    /// Returns the constant's telemetry value.
    string value() const pure nothrow @nogc
    {
        return entries[ordinal_].value;
    }

    /// Returns a fresh array of constants in declaration order.
    static AiObservationMetricAttributes[] values() pure nothrow
    {
        auto values = new AiObservationMetricAttributes[entries.length];
        foreach (i, ref value; values)
            value = AiObservationMetricAttributes(cast(int) i);
        return values;
    }

    /// Looks up a constant by its exact name.
    static AiObservationMetricAttributes valueOf(string name)
    {
        return AiObservationMetricAttributes(conventionOrdinal(name, entries,
                "flint.ai.observation.conventions.AiObservationMetricAttributes"));
    }

    /// Returns the enum constant's name.
    string toString() const pure nothrow @nogc
    {
        return name();
    }
}

/// Metric names for AI client operations.
struct AiObservationMetricNames
{
    /// Telemetry value `gen_ai.client.operation.duration`.
    static immutable AiObservationMetricNames OPERATION_DURATION = AiObservationMetricNames(0);

    /// Telemetry value `gen_ai.client.token.usage`.
    static immutable AiObservationMetricNames TOKEN_USAGE = AiObservationMetricNames(1);

    private static immutable ConventionEntry[2] entries = [
        ConventionEntry("OPERATION_DURATION", "gen_ai.client.operation.duration"),
        ConventionEntry("TOKEN_USAGE", "gen_ai.client.token.usage"),
    ];

    private int ordinal_;

    private this(int ordinal) pure nothrow @nogc
    {
        ordinal_ = ordinal;
    }

    /// Returns the enum constant's name.
    string name() const pure nothrow @nogc
    {
        return entries[ordinal_].name;
    }

    /// Returns the enum constant's zero-based declaration index.
    int ordinal() const pure nothrow @nogc
    {
        return ordinal_;
    }

    /// Returns the constant's telemetry value.
    string value() const pure nothrow @nogc
    {
        return entries[ordinal_].value;
    }

    /// Returns a fresh array of constants in declaration order.
    static AiObservationMetricNames[] values() pure nothrow
    {
        auto values = new AiObservationMetricNames[entries.length];
        foreach (i, ref value; values)
            value = AiObservationMetricNames(cast(int) i);
        return values;
    }

    /// Looks up a constant by its exact name.
    static AiObservationMetricNames valueOf(string name)
    {
        return AiObservationMetricNames(conventionOrdinal(name, entries,
                "flint.ai.observation.conventions.AiObservationMetricNames"));
    }

    /// Returns the enum constant's name.
    string toString() const pure nothrow @nogc
    {
        return name();
    }
}

/// Operation names used to observe AI systems.
struct AiOperationType
{
    /// Telemetry value `chat`.
    static immutable AiOperationType CHAT = AiOperationType(0);

    /// Telemetry value `decision`.
    static immutable AiOperationType DECISION = AiOperationType(1);

    /// Telemetry value `embedding`.
    static immutable AiOperationType EMBEDDING = AiOperationType(2);

    /// Telemetry value `execute_tool`.
    static immutable AiOperationType EXECUTE_TOOL = AiOperationType(3);

    /// Telemetry value `framework`.
    static immutable AiOperationType FRAMEWORK = AiOperationType(4);

    /// Telemetry value `image`.
    static immutable AiOperationType IMAGE = AiOperationType(5);

    /// Telemetry value `text_completion`.
    static immutable AiOperationType TEXT_COMPLETION = AiOperationType(6);

    /// Telemetry value `text_to_speech`.
    static immutable AiOperationType TEXT_TO_SPEECH = AiOperationType(7);

    /// Telemetry value `transcription`.
    static immutable AiOperationType TRANSCRIPTION = AiOperationType(8);

    private static immutable ConventionEntry[9] entries = [
        ConventionEntry("CHAT", "chat"), ConventionEntry("DECISION", "decision"),
        ConventionEntry("EMBEDDING", "embedding"), ConventionEntry("EXECUTE_TOOL", "execute_tool"),
        ConventionEntry("FRAMEWORK", "framework"), ConventionEntry("IMAGE", "image"),
        ConventionEntry("TEXT_COMPLETION", "text_completion"),
        ConventionEntry("TEXT_TO_SPEECH", "text_to_speech"),
        ConventionEntry("TRANSCRIPTION", "transcription"),
    ];

    private int ordinal_;

    private this(int ordinal) pure nothrow @nogc
    {
        ordinal_ = ordinal;
    }

    /// Returns the enum constant's name.
    string name() const pure nothrow @nogc
    {
        return entries[ordinal_].name;
    }

    /// Returns the enum constant's zero-based declaration index.
    int ordinal() const pure nothrow @nogc
    {
        return ordinal_;
    }

    /// Returns the constant's telemetry value.
    string value() const pure nothrow @nogc
    {
        return entries[ordinal_].value;
    }

    /// Returns a fresh array of constants in declaration order.
    static AiOperationType[] values() pure nothrow
    {
        auto values = new AiOperationType[entries.length];
        foreach (i, ref value; values)
            value = AiOperationType(cast(int) i);
        return values;
    }

    /// Looks up a constant by its exact name.
    static AiOperationType valueOf(string name)
    {
        return AiOperationType(conventionOrdinal(name, entries, "flint.ai.observation.conventions.AiOperationType"));
    }

    /// Returns the enum constant's name.
    string toString() const pure nothrow @nogc
    {
        return name();
    }
}

/// Telemetry identifiers for model providers.
struct AiProvider
{
    /// Telemetry value `anthropic`.
    static immutable AiProvider ANTHROPIC = AiProvider(0);

    /// Telemetry value `bedrock_converse`.
    static immutable AiProvider BEDROCK_CONVERSE = AiProvider(1);

    /// Telemetry value `deepseek`.
    static immutable AiProvider DEEPSEEK = AiProvider(2);

    /// Telemetry value `elevenlabs`.
    static immutable AiProvider ELEVENLABS = AiProvider(3);

    /// Telemetry value `google_genai`.
    static immutable AiProvider GOOGLE_GENAI_AI = AiProvider(4);

    /// Telemetry value `mistral_ai`.
    static immutable AiProvider MISTRAL_AI = AiProvider(5);

    /// Telemetry value `ollama`.
    static immutable AiProvider OLLAMA = AiProvider(6);

    /// Telemetry value `onnx`.
    static immutable AiProvider ONNX = AiProvider(7);

    /// Telemetry value `openai`.
    static immutable AiProvider OPENAI = AiProvider(8);

    /// Telemetry value `spring_ai`.
    static immutable AiProvider FLINT_AI = AiProvider(9);

    /// Telemetry value `stability_ai`.
    static immutable AiProvider STABILITY_AI = AiProvider(10);

    /// Telemetry value `systemone`.
    static immutable AiProvider SYSTEMONE = AiProvider(11);

    /// Telemetry value `vertex_ai`.
    static immutable AiProvider VERTEX_AI = AiProvider(12);

    private static immutable ConventionEntry[13] entries = [
        ConventionEntry("ANTHROPIC", "anthropic"),
        ConventionEntry("BEDROCK_CONVERSE", "bedrock_converse"),
        ConventionEntry("DEEPSEEK", "deepseek"), ConventionEntry("ELEVENLABS", "elevenlabs"),
        ConventionEntry("GOOGLE_GENAI_AI", "google_genai"),
        ConventionEntry("MISTRAL_AI", "mistral_ai"), ConventionEntry("OLLAMA", "ollama"),
        ConventionEntry("ONNX", "onnx"), ConventionEntry("OPENAI", "openai"),
        ConventionEntry("FLINT_AI", "spring_ai"), ConventionEntry("STABILITY_AI", "stability_ai"),
        ConventionEntry("SYSTEMONE", "systemone"), ConventionEntry("VERTEX_AI", "vertex_ai"),
    ];

    private int ordinal_;

    private this(int ordinal) pure nothrow @nogc
    {
        ordinal_ = ordinal;
    }

    /// Returns the enum constant's name.
    string name() const pure nothrow @nogc
    {
        return entries[ordinal_].name;
    }

    /// Returns the enum constant's zero-based declaration index.
    int ordinal() const pure nothrow @nogc
    {
        return ordinal_;
    }

    /// Returns the constant's telemetry value.
    string value() const pure nothrow @nogc
    {
        return entries[ordinal_].value;
    }

    /// Returns a fresh array of constants in declaration order.
    static AiProvider[] values() pure nothrow
    {
        auto values = new AiProvider[entries.length];
        foreach (i, ref value; values)
            value = AiProvider(cast(int) i);
        return values;
    }

    /// Looks up a constant by its exact name.
    static AiProvider valueOf(string name)
    {
        return AiProvider(conventionOrdinal(name, entries, "flint.ai.observation.conventions.AiProvider"));
    }

    /// Returns the enum constant's name.
    string toString() const pure nothrow @nogc
    {
        return name();
    }
}

/// Categories of tokens counted in AI operations.
struct AiTokenType
{
    /// Telemetry value `input`.
    static immutable AiTokenType INPUT = AiTokenType(0);

    /// Telemetry value `output`.
    static immutable AiTokenType OUTPUT = AiTokenType(1);

    /// Telemetry value `total`.
    static immutable AiTokenType TOTAL = AiTokenType(2);

    private static immutable ConventionEntry[3] entries = [
        ConventionEntry("INPUT", "input"), ConventionEntry("OUTPUT", "output"),
        ConventionEntry("TOTAL", "total"),
    ];

    private int ordinal_;

    private this(int ordinal) pure nothrow @nogc
    {
        ordinal_ = ordinal;
    }

    /// Returns the enum constant's name.
    string name() const pure nothrow @nogc
    {
        return entries[ordinal_].name;
    }

    /// Returns the enum constant's zero-based declaration index.
    int ordinal() const pure nothrow @nogc
    {
        return ordinal_;
    }

    /// Returns the constant's telemetry value.
    string value() const pure nothrow @nogc
    {
        return entries[ordinal_].value;
    }

    /// Returns a fresh array of constants in declaration order.
    static AiTokenType[] values() pure nothrow
    {
        auto values = new AiTokenType[entries.length];
        foreach (i, ref value; values)
            value = AiTokenType(cast(int) i);
        return values;
    }

    /// Looks up a constant by its exact name.
    static AiTokenType valueOf(string name)
    {
        return AiTokenType(conventionOrdinal(name, entries, "flint.ai.observation.conventions.AiTokenType"));
    }

    /// Returns the enum constant's name.
    string toString() const pure nothrow @nogc
    {
        return name();
    }
}

/// The kind of Flint AI component being observed.
struct FlintAiKind
{
    /// Telemetry value `advisor`.
    static immutable FlintAiKind ADVISOR = FlintAiKind(0);

    /// Telemetry value `chat_client`.
    static immutable FlintAiKind CHAT_CLIENT = FlintAiKind(1);

    /// Telemetry value `tool_call`.
    static immutable FlintAiKind TOOL_CALL = FlintAiKind(2);

    /// Telemetry value `vector_store`.
    static immutable FlintAiKind VECTOR_STORE = FlintAiKind(3);

    private static immutable ConventionEntry[4] entries = [
        ConventionEntry("ADVISOR", "advisor"), ConventionEntry("CHAT_CLIENT", "chat_client"),
        ConventionEntry("TOOL_CALL", "tool_call"), ConventionEntry("VECTOR_STORE", "vector_store"),
    ];

    private int ordinal_;

    private this(int ordinal) pure nothrow @nogc
    {
        ordinal_ = ordinal;
    }

    /// Returns the enum constant's name.
    string name() const pure nothrow @nogc
    {
        return entries[ordinal_].name;
    }

    /// Returns the enum constant's zero-based declaration index.
    int ordinal() const pure nothrow @nogc
    {
        return ordinal_;
    }

    /// Returns the constant's telemetry value.
    string value() const pure nothrow @nogc
    {
        return entries[ordinal_].value;
    }

    /// Returns a fresh array of constants in declaration order.
    static FlintAiKind[] values() pure nothrow
    {
        auto values = new FlintAiKind[entries.length];
        foreach (i, ref value; values)
            value = FlintAiKind(cast(int) i);
        return values;
    }

    /// Looks up a constant by its exact name.
    static FlintAiKind valueOf(string name)
    {
        return FlintAiKind(conventionOrdinal(name, entries, "flint.ai.observation.conventions.FlintAiKind"));
    }

    /// Returns the enum constant's name.
    string toString() const pure nothrow @nogc
    {
        return name();
    }
}

/// Attribute keys for vector store operations.
struct VectorStoreObservationAttributes
{
    private alias Self = VectorStoreObservationAttributes;

    /// Telemetry value `db.collection.name`.
    static immutable VectorStoreObservationAttributes DB_COLLECTION_NAME = VectorStoreObservationAttributes(0);

    /// Telemetry value `db.namespace`.
    static immutable VectorStoreObservationAttributes DB_NAMESPACE = VectorStoreObservationAttributes(1);

    /// Telemetry value `db.operation.name`.
    static immutable VectorStoreObservationAttributes DB_OPERATION_NAME = VectorStoreObservationAttributes(2);

    /// Telemetry value `db.record.id`.
    static immutable VectorStoreObservationAttributes DB_RECORD_ID = VectorStoreObservationAttributes(3);

    /// Telemetry value `db.system`.
    static immutable VectorStoreObservationAttributes DB_SYSTEM = VectorStoreObservationAttributes(4);

    /// Telemetry value `db.search.similarity_metric`.
    static immutable VectorStoreObservationAttributes DB_SEARCH_SIMILARITY_METRIC = VectorStoreObservationAttributes(5);

    /// Telemetry value `db.vector.dimension_count`.
    static immutable VectorStoreObservationAttributes DB_VECTOR_DIMENSION_COUNT = VectorStoreObservationAttributes(6);

    /// Telemetry value `db.vector.field_name`.
    static immutable VectorStoreObservationAttributes DB_VECTOR_FIELD_NAME = VectorStoreObservationAttributes(7);

    /// Telemetry value `db.vector.query.content`.
    static immutable VectorStoreObservationAttributes DB_VECTOR_QUERY_CONTENT = VectorStoreObservationAttributes(8);

    /// Telemetry value `db.vector.query.filter`.
    static immutable VectorStoreObservationAttributes DB_VECTOR_QUERY_FILTER = VectorStoreObservationAttributes(9);

    /// Telemetry value `db.vector.query.response.documents`.
    static immutable Self DB_VECTOR_QUERY_RESPONSE_DOCUMENTS = Self(10);

    /// Telemetry value `db.vector.query.similarity_threshold`.
    static immutable Self DB_VECTOR_QUERY_SIMILARITY_THRESHOLD = Self(11);

    /// Telemetry value `db.vector.query.top_k`.
    static immutable VectorStoreObservationAttributes DB_VECTOR_QUERY_TOP_K = VectorStoreObservationAttributes(12);

    private static immutable ConventionEntry[13] entries = [
        ConventionEntry("DB_COLLECTION_NAME", "db.collection.name"),
        ConventionEntry("DB_NAMESPACE", "db.namespace"),
        ConventionEntry("DB_OPERATION_NAME", "db.operation.name"),
        ConventionEntry("DB_RECORD_ID", "db.record.id"), ConventionEntry("DB_SYSTEM",
                "db.system"),
        ConventionEntry("DB_SEARCH_SIMILARITY_METRIC", "db.search.similarity_metric"),
        ConventionEntry("DB_VECTOR_DIMENSION_COUNT", "db.vector.dimension_count"),
        ConventionEntry("DB_VECTOR_FIELD_NAME", "db.vector.field_name"),
        ConventionEntry("DB_VECTOR_QUERY_CONTENT", "db.vector.query.content"),
        ConventionEntry("DB_VECTOR_QUERY_FILTER", "db.vector.query.filter"),
        ConventionEntry("DB_VECTOR_QUERY_RESPONSE_DOCUMENTS", "db.vector.query.response.documents"),
        ConventionEntry("DB_VECTOR_QUERY_SIMILARITY_THRESHOLD", "db.vector.query.similarity_threshold"),
        ConventionEntry("DB_VECTOR_QUERY_TOP_K", "db.vector.query.top_k"),
    ];

    private int ordinal_;

    private this(int ordinal) pure nothrow @nogc
    {
        ordinal_ = ordinal;
    }

    /// Returns the enum constant's name.
    string name() const pure nothrow @nogc
    {
        return entries[ordinal_].name;
    }

    /// Returns the enum constant's zero-based declaration index.
    int ordinal() const pure nothrow @nogc
    {
        return ordinal_;
    }

    /// Returns the constant's telemetry value.
    string value() const pure nothrow @nogc
    {
        return entries[ordinal_].value;
    }

    /// Returns a fresh array of constants in declaration order.
    static VectorStoreObservationAttributes[] values() pure nothrow
    {
        auto values = new VectorStoreObservationAttributes[entries.length];
        foreach (i, ref value; values)
            value = VectorStoreObservationAttributes(cast(int) i);
        return values;
    }

    /// Looks up a constant by its exact name.
    static VectorStoreObservationAttributes valueOf(string name)
    {
        return VectorStoreObservationAttributes(conventionOrdinal(name, entries,
                "flint.ai.observation.conventions.VectorStoreObservationAttributes"));
    }

    /// Returns the enum constant's name.
    string toString() const pure nothrow @nogc
    {
        return name();
    }
}

/// Telemetry identifiers for vector store providers.
struct VectorStoreProvider
{
    /// Telemetry value `azure`.
    static immutable VectorStoreProvider AZURE = VectorStoreProvider(0);

    /// Telemetry value `cassandra`.
    static immutable VectorStoreProvider CASSANDRA = VectorStoreProvider(1);

    /// Telemetry value `chroma`.
    static immutable VectorStoreProvider CHROMA = VectorStoreProvider(2);

    /// Telemetry value `couchbase`.
    static immutable VectorStoreProvider COUCHBASE = VectorStoreProvider(3);

    /// Telemetry value `elasticsearch`.
    static immutable VectorStoreProvider ELASTICSEARCH = VectorStoreProvider(4);

    /// Telemetry value `gemfire`.
    static immutable VectorStoreProvider GEMFIRE = VectorStoreProvider(5);

    /// Telemetry value `mariadb`.
    static immutable VectorStoreProvider MARIADB = VectorStoreProvider(6);

    /// Telemetry value `milvus`.
    static immutable VectorStoreProvider MILVUS = VectorStoreProvider(7);

    /// Telemetry value `mongodb`.
    static immutable VectorStoreProvider MONGODB = VectorStoreProvider(8);

    /// Telemetry value `neo4j`.
    static immutable VectorStoreProvider NEO4J = VectorStoreProvider(9);

    /// Telemetry value `opensearch`.
    static immutable VectorStoreProvider OPENSEARCH = VectorStoreProvider(10);

    /// Telemetry value `oracle`.
    static immutable VectorStoreProvider ORACLE = VectorStoreProvider(11);

    /// Telemetry value `pg_vector`.
    static immutable VectorStoreProvider PG_VECTOR = VectorStoreProvider(12);

    /// Telemetry value `pinecone`.
    static immutable VectorStoreProvider PINECONE = VectorStoreProvider(13);

    /// Telemetry value `qdrant`.
    static immutable VectorStoreProvider QDRANT = VectorStoreProvider(14);

    /// Telemetry value `redis`.
    static immutable VectorStoreProvider REDIS = VectorStoreProvider(15);

    /// Telemetry value `s3_vector`.
    static immutable VectorStoreProvider S3_VECTOR = VectorStoreProvider(16);

    /// Telemetry value `simple`.
    static immutable VectorStoreProvider SIMPLE = VectorStoreProvider(17);

    /// Telemetry value `typesense`.
    static immutable VectorStoreProvider TYPESENSE = VectorStoreProvider(18);

    /// Telemetry value `weaviate`.
    static immutable VectorStoreProvider WEAVIATE = VectorStoreProvider(19);

    private static immutable ConventionEntry[20] entries = [
        ConventionEntry("AZURE", "azure"), ConventionEntry("CASSANDRA", "cassandra"),
        ConventionEntry("CHROMA", "chroma"), ConventionEntry("COUCHBASE", "couchbase"),
        ConventionEntry("ELASTICSEARCH", "elasticsearch"), ConventionEntry("GEMFIRE", "gemfire"),
        ConventionEntry("MARIADB", "mariadb"), ConventionEntry("MILVUS", "milvus"),
        ConventionEntry("MONGODB", "mongodb"), ConventionEntry("NEO4J", "neo4j"),
        ConventionEntry("OPENSEARCH", "opensearch"), ConventionEntry("ORACLE", "oracle"),
        ConventionEntry("PG_VECTOR", "pg_vector"), ConventionEntry("PINECONE", "pinecone"),
        ConventionEntry("QDRANT", "qdrant"), ConventionEntry("REDIS", "redis"),
        ConventionEntry("S3_VECTOR", "s3_vector"), ConventionEntry("SIMPLE", "simple"),
        ConventionEntry("TYPESENSE", "typesense"), ConventionEntry("WEAVIATE", "weaviate"),
    ];

    private int ordinal_;

    private this(int ordinal) pure nothrow @nogc
    {
        ordinal_ = ordinal;
    }

    /// Returns the enum constant's name.
    string name() const pure nothrow @nogc
    {
        return entries[ordinal_].name;
    }

    /// Returns the enum constant's zero-based declaration index.
    int ordinal() const pure nothrow @nogc
    {
        return ordinal_;
    }

    /// Returns the constant's telemetry value.
    string value() const pure nothrow @nogc
    {
        return entries[ordinal_].value;
    }

    /// Returns a fresh array of constants in declaration order.
    static VectorStoreProvider[] values() pure nothrow
    {
        auto values = new VectorStoreProvider[entries.length];
        foreach (i, ref value; values)
            value = VectorStoreProvider(cast(int) i);
        return values;
    }

    /// Looks up a constant by its exact name.
    static VectorStoreProvider valueOf(string name)
    {
        return VectorStoreProvider(conventionOrdinal(name, entries,
                "flint.ai.observation.conventions.VectorStoreProvider"));
    }

    /// Returns the enum constant's name.
    string toString() const pure nothrow @nogc
    {
        return name();
    }
}

/// Similarity metric names reported by vector stores.
struct VectorStoreSimilarityMetric
{
    /// Telemetry value `cosine`.
    static immutable VectorStoreSimilarityMetric COSINE = VectorStoreSimilarityMetric(0);

    /// Telemetry value `dot`.
    static immutable VectorStoreSimilarityMetric DOT = VectorStoreSimilarityMetric(1);

    /// Telemetry value `euclidean`.
    static immutable VectorStoreSimilarityMetric EUCLIDEAN = VectorStoreSimilarityMetric(2);

    /// Telemetry value `manhattan`.
    static immutable VectorStoreSimilarityMetric MANHATTAN = VectorStoreSimilarityMetric(3);

    private static immutable ConventionEntry[4] entries = [
        ConventionEntry("COSINE", "cosine"), ConventionEntry("DOT", "dot"),
        ConventionEntry("EUCLIDEAN", "euclidean"), ConventionEntry("MANHATTAN", "manhattan"),
    ];

    private int ordinal_;

    private this(int ordinal) pure nothrow @nogc
    {
        ordinal_ = ordinal;
    }

    /// Returns the enum constant's name.
    string name() const pure nothrow @nogc
    {
        return entries[ordinal_].name;
    }

    /// Returns the enum constant's zero-based declaration index.
    int ordinal() const pure nothrow @nogc
    {
        return ordinal_;
    }

    /// Returns the constant's telemetry value.
    string value() const pure nothrow @nogc
    {
        return entries[ordinal_].value;
    }

    /// Returns a fresh array of constants in declaration order.
    static VectorStoreSimilarityMetric[] values() pure nothrow
    {
        auto values = new VectorStoreSimilarityMetric[entries.length];
        foreach (i, ref value; values)
            value = VectorStoreSimilarityMetric(cast(int) i);
        return values;
    }

    /// Looks up a constant by its exact name.
    static VectorStoreSimilarityMetric valueOf(string name)
    {
        return VectorStoreSimilarityMetric(conventionOrdinal(name, entries,
                "flint.ai.observation.conventions.VectorStoreSimilarityMetric"));
    }

    /// Returns the enum constant's name.
    string toString() const pure nothrow @nogc
    {
        return name();
    }
}
