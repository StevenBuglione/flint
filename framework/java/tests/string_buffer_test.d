module string_buffer_test;

import flint.java.lang : CanonicalStringBuffer = StringBuffer;
import flint.java.lang.stringbuffer : StringBuffer;

@safe:
static assert(is(CanonicalStringBuffer == StringBuffer));

@("StringBuffer keeps UTF-16 units and appends Java's null text")
unittest
{
    auto buffer = new StringBuffer;
    assert(buffer.length() == 0);
    assert(buffer.toString() == "");
    assert(buffer.append("A\U0001F680\u00E9") is buffer);
    assert(buffer.length() == 4); // A, high surrogate, low surrogate, e-acute
    assert(buffer.toString() == "A\U0001F680\u00E9");

    string absent;
    assert(buffer.append(absent) is buffer);
    assert(buffer.toString() == "A\U0001F680\u00E9null");
    assert(buffer.length() == 8);
}

@("StringBuffer constructors and unpaired surrogates follow R14")
unittest
{
    string absent;
    auto empty = new StringBuffer(absent);
    assert(empty.length() == 0);
    assert(empty.toString() == "");
    assert(new StringBuffer("abc").toString() == "abc");

    auto lone = new StringBuffer;
    lone.append(cast(wchar) 0xD83D);
    assert(lone.length() == 1);
    assert(lone.toString() == "\uFFFD");

    auto pair = new StringBuffer;
    pair.append(cast(wchar) 0xD83D).append(cast(wchar) 0xDE80);
    assert(pair.length() == 2);
    assert(pair.toString() == "\U0001F680");
}
