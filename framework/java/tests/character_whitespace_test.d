/// Flint tests for Java Character's whitespace classification.
module flint.java.character_whitespace_test;

import flint.java.lang.character : isWhitespace;

@safe:

@("Character whitespace agrees with all code points from the Java 21 oracle")
unittest
{
    static immutable dchar[] whitespace = [
        0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x001C, 0x001D, 0x001E, 0x001F, 0x0020, 0x1680,
        0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2008, 0x2009, 0x200A, 0x2028,
        0x2029, 0x205F, 0x3000,
    ];
    size_t nextWhitespace;
    foreach (uint codePoint; 0 .. 0x110000)
    {
        const expected = nextWhitespace < whitespace.length && codePoint == whitespace[nextWhitespace];
        assert(isWhitespace(cast(dchar) codePoint) == expected);
        if (expected)
            ++nextWhitespace;
    }
    assert(nextWhitespace == whitespace.length);
    assert(!isWhitespace(cast(dchar) 0x110000));
    assert(!isWhitespace(dchar.max));
}
