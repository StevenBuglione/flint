module api_key_tests;

import flint.ai.model : ApiKey, NoopApiKey, SimpleApiKey;
import flint.java.lang : IllegalArgumentException;
import std.exception : assertThrown;

@safe:

@("simple API key preserves its value and redacts its string representation")
unittest
{
    const value = "  example-test-key  ";
    const key = new SimpleApiKey(value);
    assert(key.value() == value);

    ApiKey provider = new SimpleApiKey(value);
    assert(provider.getValue() == value);
    assert((cast(SimpleApiKey) provider).toString() == "SimpleApiKey{value='***'}");

    assert(new SimpleApiKey("").getValue() == "");
    assertThrown!IllegalArgumentException(new SimpleApiKey(null));
}

@("simple API keys use record equality and Java string hashing")
unittest
{
    auto first = new SimpleApiKey("Aé😀");
    auto second = new SimpleApiKey("Aé😀");
    assert(first !is second);
    assert(first == second);
    assert(first.hashCode() == 3_933_227);
    assert(first.hashCode() == second.hashCode());
    assert(!first.equals(new SimpleApiKey("other-key")));
    assert(!first.equals(new NoopApiKey()));
    assert(!first.equals(null));
}

@("no-op API key requests omission of the credential")
unittest
{
    ApiKey provider = new NoopApiKey();
    assert(provider.getValue() == "");
}
