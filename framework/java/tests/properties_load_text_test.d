module properties_load_text_test;

import flint.java.io : ByteArrayInputStream;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : Properties;
import std.algorithm.sorting : sort;
import std.exception : assertThrown;

@safe:

private string[] keysOf(Properties properties)
{
    auto keys = properties.keySet().toArray();
    keys.sort;
    return keys;
}

private void assertSame(Properties asText, Properties asBytes)
{
    const keys = keysOf(asText);
    const byteKeys = keysOf(asBytes);
    assert(keys == byteKeys);
    foreach (key; keys)
        assert(asText.getProperty(key) == asBytes.getProperty(key));
    assert(asText.size() == asBytes.size());
}

@("Properties text and byte loading agree on a lone trailing backslash and its continuations") unittest
{
    // Java's LineReader returns an empty line, stored as ("", ""), when a line that held only
    // a trailing backslash reaches the end of the input; it returns none when blank lines follow
    // a continuation. The byte reader ports that state machine, so the text reader must match it.
    foreach (text; [
        "\\", "\\\n", "\\\n\\", " \\", "\n\\", "\\\n\n", "\\\n\n\n", "a=b\\\n\nc=d",
        "a=b\\\n \nc=d", "\\\n#ignored=1\na=b", "a=b\\\n#value=1",
    ])
    {
        auto asText = new Properties;
        auto asBytes = new Properties;
        asText.load(text);
        asBytes.load(new ByteArrayInputStream(cast(ubyte[]) text.dup));
        assertSame(asText, asBytes);
    }
}

@("Properties text loading matches Java's empty entry for a backslash-only line") unittest
{
    auto properties = new Properties;
    properties.load("\\");
    assert(properties.size() == 1);
    assert(properties.containsKey("") && properties.getProperty("") == "");

    properties = new Properties;
    properties.load("\\\n");
    assert(properties.size() == 1 && properties.containsKey(""));

    properties = new Properties;
    properties.load("\\\n\n");
    assert(properties.size() == 0);
}

@("Properties text loading treats a comment only while the logical line is empty") unittest
{
    auto properties = new Properties;
    properties.load("\\\n#ignored=1\na=b\\\n#value=1");
    assert(properties.size() == 1 && properties.getProperty("a") == "b#value=1");
}

@("Properties text loading still rejects a malformed unicode escape") unittest
{
    auto properties = new Properties;
    assertThrown!IllegalArgumentException(properties.load("bad=\\uD83D\\uDE0Z"));
}
