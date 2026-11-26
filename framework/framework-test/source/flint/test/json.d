/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/main/java/org/springframework/test/json/ (JsonComparator.java, JsonCompareMode.java,
JsonComparison.java).
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors. The built-in comparator uses the Jackson tree (D-TEST-1).
+/
module flint.test.json;

import flint.jackson.databind : JsonMapper;
import flint.jackson.databind.node : JsonNode;
import flint.java.lang : AssertionError, IllegalStateException;
import std.typecons : Nullable;

@safe:

/// Whether the comparison permits extra object fields and ignores array order.
enum JsonCompareMode
{
    STRICT, /// Exact object members and ordered array entries.
    LENIENT, /// Extra object members and reordered array entries are allowed.
}

/// The result and optional diagnostic of a JSON comparison.
final class JsonComparison
{
    /// The comparison outcome.
    enum Result
    {
        MATCH, /// The documents match in the selected mode.
        MISMATCH, /// The documents differ in the selected mode.
    }

    private Result result;
    private Nullable!string message;

    private this(Result result, Nullable!string message) pure nothrow @nogc
    {
        this.result = result;
        this.message = message;
    }

    /// A successful comparison.
    static JsonComparison match()
    {
        return new JsonComparison(Result.MATCH, Nullable!string.init);
    }

    /// A comparison with the given mismatch message.
    static JsonComparison mismatch(string message)
    {
        return new JsonComparison(Result.MISMATCH, Nullable!string(message));
    }

    /// The comparison outcome.
    Result getResult() const pure nothrow @nogc
    {
        return result;
    }

    /// The diagnostic, absent for a match.
    Nullable!string getMessage() const pure nothrow @nogc
    {
        return message;
    }
}

/// A strategy for comparing two JSON documents (R3, R5, R9).
interface JsonComparator
{
    /// Compare both inputs. An absent string is distinct from the JSON literal `null`.
    JsonComparison compare(Nullable!string expectedJson, Nullable!string actualJson);

    /// Assert that the two documents match, reporting the comparator's diagnostic on a mismatch.
    void assertIsMatch(Nullable!string expectedJson, Nullable!string actualJson);

    /// Spring's default method for implementations of `compare` (R3).
    mixin template Defaults()
    {
        void assertIsMatch(Nullable!string expectedJson, Nullable!string actualJson)
        {
            JsonComparator comparator = this;
            auto comparison = comparator.compare(expectedJson, actualJson);
            if (comparison.getResult() == JsonComparison.Result.MISMATCH)
                throw new AssertionError(comparison.getMessage().get());
        }
    }

    /// A built-in comparator using Jackson and the selected mode (D-TEST-1).
    static JsonComparator of(JsonCompareMode compareMode)
    {
        return new JacksonComparator(compareMode);
    }
}

private final class JacksonComparator : JsonComparator
{
    mixin JsonComparator.Defaults;

    private JsonMapper mapper;
    private bool strict;

    this(JsonCompareMode compareMode)
    {
        mapper = new JsonMapper;
        strict = compareMode == JsonCompareMode.STRICT;
    }

    override JsonComparison compare(Nullable!string expectedJson, Nullable!string actualJson)
    {
        if (actualJson.isNull)
            return expectedJson.isNull ? JsonComparison.match() : JsonComparison.mismatch("Expected null JSON");
        if (expectedJson.isNull)
            return JsonComparison.mismatch("Expected non-null JSON");

        const expected = expectedJson.get();
        const actual = actualJson.get();
        if (matches(parse(expected), parse(actual)))
            return JsonComparison.match();
        return JsonComparison.mismatch("JSON content expected:<" ~ expected ~ "> but was:<" ~ actual ~ ">");
    }

    private JsonNode parse(string json)
    {
        JsonNode node;
        try
            node = mapper.readTree(json);
        catch (Exception invalidJson)
            throw new IllegalStateException(invalidJson.msg, invalidJson);
        if (node.isMissingNode())
            throw new IllegalStateException("No JSON content");
        return node;
    }

    private bool matches(JsonNode expected, JsonNode actual)
    {
        if (actual is null || expected.getNodeType() != actual.getNodeType())
            return false;
        if (expected.isObject())
            return matchesObject(expected, actual);
        if (expected.isArray())
            return matchesArray(expected, actual);
        if (expected.isNumber())
            return expected.doubleValue() == actual.doubleValue();
        return expected == actual;
    }

    private bool matchesObject(JsonNode expected, JsonNode actual)
    {
        if (strict && expected.size() != actual.size())
            return false;
        foreach (name; expected.propertyNames())
            if (!matches(expected.get(name), actual.get(name)))
                return false;
        return true;
    }

    private bool matchesArray(JsonNode expected, JsonNode actual)
    {
        const size = expected.size();
        if (size != actual.size())
            return false;
        if (!strict && size > 1)
            return matchesUnordered(expected, actual, size);
        foreach (index; 0 .. size)
            if (!matches(expected.get(index), actual.get(index)))
                return false;
        return true;
    }

    private bool matchesUnordered(JsonNode expected, JsonNode actual, int size)
    {
        // Each actual entry can satisfy one expected entry. An earlier assignment may need to move
        // when a later expected object has a stricter set of keys.
        auto actualOwner = new int[size];
        auto expectedMatch = new int[size];
        auto parents = new int[size];
        auto queue = new int[size];
        actualOwner[] = -1;
        expectedMatch[] = -1;
        foreach (expectedIndex; 0 .. size)
        {
            parents[] = -1;
            const free = findAvailable(expected, actual, expectedIndex, actualOwner, parents, queue);
            if (free < 0)
                return false;
            for (int index = free; index >= 0;)
            {
                const owner = parents[index];
                actualOwner[index] = owner;
                const previousMatch = expectedMatch[owner];
                expectedMatch[owner] = index;
                index = previousMatch;
            }
        }
        return true;
    }

    private int findAvailable(JsonNode expected, JsonNode actual, int expectedIndex,
            scope const(int)[] actualOwner, scope int[] parents, scope int[] queue)
    {
        queue[0] = expectedIndex;
        size_t end = 1;
        for (size_t next = 0; next < end; ++next)
        {
            const owner = queue[next];
            auto value = expected.get(owner);
            foreach (index; 0 .. actual.size())
            {
                if (parents[index] >= 0 || !matches(value, actual.get(index)))
                    continue;
                parents[index] = owner;
                if (actualOwner[index] < 0)
                    return index;
                queue[end++] = actualOwner[index];
            }
        }
        return -1;
    }
}
