/// Helpers shared by the ported read-feature tests (JacksonCoreTestBase's createParser and verifyException).
module read_test_support;

import flint.jackson.core : JsonParser, JsonToken;
import flint.jackson.core.json : JsonFactory, JsonReadFeature;

@safe:

/// A parser over `doc` from a factory with `features` enabled. Flint has one byte parser, so Jackson's input modes
/// (stream, throttled stream, reader, data input) all read through it.
JsonParser parserWith(string doc, JsonReadFeature[] features...)
{
    auto builder = JsonFactory.builder();
    foreach (f; features)
        builder = builder.enable(f);
    return builder.build().createParser(doc);
}

/// JacksonCoreTestBase.verifyException: a case-insensitive substring match.
void verifyException(Exception e, string expected)
{
    import std.string : indexOf;
    import std.uni : toLower;

    assert(e.msg.toLower().indexOf(expected.toLower()) >= 0, "expected '" ~ expected ~ "' in: " ~ e.msg);
}

/// The next token fails with a message containing `expected`.
void nextFails(JsonParser p, string expected)
{
    try
    {
        p.nextToken();
        assert(false, "No exception thrown, expected: " ~ expected);
    }
    catch (Exception e)
        verifyException(e, expected);
}

/// Jackson's end of input (null from nextToken) is NOT_AVAILABLE in Flint.
void assertEnd(JsonParser p)
{
    assert(p.nextToken() == JsonToken.NOT_AVAILABLE);
}
