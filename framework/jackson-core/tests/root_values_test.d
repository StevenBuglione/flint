/// Root-level number ends and invalid tokens, as Jackson 3.1.8's UTF8StreamJsonParser reports them. The inputs of
/// brokenNumber and invalidToken come from TestRootValues; the rest pin _verifyRootSpace, _checkMatchEnd and
/// _reportInvalidToken around them.
module root_values_test;

import flint.jackson.core : JsonToken;
import flint.jackson.core.exc : StreamReadException;
import read_test_support : nextFails, parserWith;

@safe:

@("a root-level number needs white space after it (TestRootValues.brokenNumber's input)")
unittest
{
    enum rootSpace = "Expected space separating root-level values";
    nextFails(parserWith("14:89:FD:D3:E7:8C"), "Unexpected character (':' (code 58)): " ~ rootSpace);
    nextFails(parserWith("1,2"), "Unexpected character (',' (code 44)): Expected space separating root-level values");
    nextFails(parserWith("1]"), "Expected space separating root-level values");
    auto spaced = parserWith("1 \t2\n3\r4");
    foreach (i; 1 .. 5)
        assert(spaced.nextToken() == JsonToken.VALUE_NUMBER_INT && spaced.getIntValue() == i);
}

@("inside an Array or Object any byte ends a number, and the next token reports it")
unittest
{
    auto array = parserWith("[1x]");
    assert(array.nextToken() == JsonToken.START_ARRAY);
    assert(array.nextToken() == JsonToken.VALUE_NUMBER_INT);
    nextFails(array, "Unexpected character ('x' (code 120)): was expecting comma to separate Array entries");
    auto object = parserWith(`{"a":1:2}`);
    assert(object.nextToken() == JsonToken.START_OBJECT);
    assert(object.nextToken() == JsonToken.PROPERTY_NAME);
    assert(object.nextToken() == JsonToken.VALUE_NUMBER_INT);
    nextFails(object, "was expecting comma to separate Object entries");
}

@("a value starting with a Java identifier character is an unrecognized token (TestRootValues.invalidToken's input)")
unittest
{
    auto p = parserWith(" A㑖C ");
    try
    {
        p.nextToken();
        assert(false);
    }
    catch (StreamReadException e)
    {
        assert(e.getOriginalMessage() == "Unrecognized token 'A\u3456C': was expecting (JSON String, Number, Array, "
                ~ "Object or token 'null', 'true' or 'false')", e.msg);
        assert(e.getLocation().getColumnNr() == 2); // the token's start
    }
    auto latin = parserWith("[\u00C4bc]");
    assert(latin.nextToken() == JsonToken.START_ARRAY);
    nextFails(latin, "Unrecognized token '\u00C4bc'");
    nextFails(parserWith("x×y"), "Unrecognized token 'x'"); // U+00D7 is no identifier part
    nextFails(parserWith("?"), "Unexpected character ('?' (code 63)): expected a valid value");
}

@("a literal runs on into a token only through an identifier part")
unittest
{
    nextFails(parserWith("truex"), "Unrecognized token 'truex'");
    auto trux = parserWith("[trux]");
    assert(trux.nextToken() == JsonToken.START_ARRAY);
    nextFails(trux, "Unrecognized token 'trux'");
    nextFails(parserWith("nul"), "Unrecognized token 'nul'");
    auto dash = parserWith("[true-1]");
    assert(dash.nextToken() == JsonToken.START_ARRAY);
    assert(dash.nextToken() == JsonToken.VALUE_TRUE);
    nextFails(dash, "was expecting comma to separate Array entries");
}

@("an unrecognized token stops at 256 UTF-16 units and adds ...")
unittest
{
    string doc = "a";
    foreach (i; 0 .. 300)
        doc ~= 'b';
    string shown = "a";
    foreach (i; 0 .. 255)
        shown ~= 'b';
    nextFails(parserWith(doc), "Unrecognized token '" ~ shown ~ "...'");
}

// Pinned 3.1.8 UTF-8 results (sol-jackson's receipt, peer-root-values-review/java.log): NaN and the Infinities end as
// _matchToken's _checkMatchEnd says, not by _verifyRootSpace, and "true×" ends at a Latin-1 non-identifier.
@("NaN and the Infinities end like literals, at any byte but an identifier part")
unittest
{
    import flint.jackson.core.json : JsonReadFeature;

    foreach (doc; ["NaN,", "Infinity,", "+Infinity,", "NaN+"])
    {
        auto p = parserWith(doc, JsonReadFeature.ALLOW_NON_NUMERIC_NUMBERS);
        assert(p.nextToken() == JsonToken.VALUE_NUMBER_FLOAT, doc);
    }
    nextFails(parserWith("NaNu", JsonReadFeature.ALLOW_NON_NUMERIC_NUMBERS), "Unrecognized token 'NaNu'");
    nextFails(parserWith("Infinityx"), "Unrecognized token 'Infinityx'"); // checked before the feature, as in Jackson
    auto t = parserWith("true×");
    assert(t.nextToken() == JsonToken.VALUE_TRUE);
}

@("the expected-value list names NaN and the Infinities once they are allowed")
unittest
{
    import flint.jackson.core.json : JsonReadFeature;

    nextFails(parserWith(" A㑖C ", JsonReadFeature.ALLOW_NON_NUMERIC_NUMBERS),
            "Unrecognized token 'A㑖C': was expecting (JSON String, Number (or 'NaN'/'+INF'/'-INF'), Array, Object "
            ~ "or token 'null', 'true' or 'false')");
    nextFails(parserWith("?", JsonReadFeature.ALLOW_NON_NUMERIC_NUMBERS),
            "expected a valid value (JSON String, Number (or 'NaN'/'+INF'/'-INF'), Array");
}
