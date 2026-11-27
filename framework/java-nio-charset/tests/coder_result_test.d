// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests against the Java SE 21 CoderResult API.
module coder_result_test;

import flint.java.lang : IllegalArgumentException, UnsupportedOperationException;
import flint.java.nio.charset.coderresult : CoderResult;
import std.exception : collectException;

@safe:

static assert(!__traits(compiles, CoderResult(cast(ubyte) 1, 0)));
static assert(!__traits(compiles, CoderResult(cast(ubyte) 2, 1)));

private bool isErrorResult(CoderResult result) pure nothrow @nogc
{
    return result.isError();
}

@("CoderResult constants, predicates, default init and length errors match Java 21")
unittest
{
    CoderResult underflow = CoderResult.UNDERFLOW;
    assert(CoderResult.init == underflow);
    assert(underflow.isUnderflow() && !underflow.isOverflow() && !isErrorResult(underflow));
    assert(!underflow.isMalformed() && !underflow.isUnmappable());
    assert(underflow.toString() == "UNDERFLOW");

    auto uo = collectException!UnsupportedOperationException(underflow.length());
    assert(uo !is null && uo.getMessage() is null);

    CoderResult overflow = CoderResult.OVERFLOW;
    assert(overflow != underflow);
    assert(!overflow.isUnderflow() && overflow.isOverflow() && !isErrorResult(overflow));
    assert(!overflow.isMalformed() && !overflow.isUnmappable());
    assert(overflow.toString() == "OVERFLOW");

    uo = collectException!UnsupportedOperationException(overflow.length());
    assert(uo !is null && uo.getMessage() is null);
}

@("CoderResult malformed and unmappable factories preserve value equality and formatting")
unittest
{
    static immutable int[] lengths = [1, 2, 4, 5, 12_345, int.max];
    static immutable string[] malformedStrings = [
        "MALFORMED[1]", "MALFORMED[2]", "MALFORMED[4]", "MALFORMED[5]", "MALFORMED[12345]",
        "MALFORMED[2147483647]"
    ];
    static immutable string[] unmappableStrings = [
        "UNMAPPABLE[1]", "UNMAPPABLE[2]", "UNMAPPABLE[4]", "UNMAPPABLE[5]", "UNMAPPABLE[12345]",
        "UNMAPPABLE[2147483647]"
    ];

    foreach (i, n; lengths)
    {
        const m1 = CoderResult.malformedForLength(n);
        const m2 = CoderResult.malformedForLength(n);
        assert(m1 == m2);
        assert(!m1.isUnderflow() && !m1.isOverflow() && m1.isError());
        assert(m1.isMalformed() && !m1.isUnmappable());
        assert(m1.length() == n);
        assert(m1.toString() == malformedStrings[i]);

        const u1 = CoderResult.unmappableForLength(n);
        const u2 = CoderResult.unmappableForLength(n);
        assert(u1 == u2);
        assert(m1 != u1);
        assert(m1 != CoderResult.UNDERFLOW && m1 != CoderResult.OVERFLOW);
        assert(u1 != CoderResult.UNDERFLOW && u1 != CoderResult.OVERFLOW);
        assert(!u1.isUnderflow() && !u1.isOverflow() && u1.isError());
        assert(!u1.isMalformed() && u1.isUnmappable());
        assert(u1.length() == n);
        assert(u1.toString() == unmappableStrings[i]);
    }
    assert(CoderResult.malformedForLength(1) != CoderResult.malformedForLength(2));
    assert(CoderResult.unmappableForLength(1) != CoderResult.unmappableForLength(2));
}

@("CoderResult rejects non-positive lengths with exact Java 21 diagnostic")
unittest
{
    foreach (bad; [0, -1, int.min])
    {
        auto mErr = collectException!IllegalArgumentException(CoderResult.malformedForLength(bad));
        assert(mErr !is null && mErr.getMessage() == "Non-positive length");

        auto uErr = collectException!IllegalArgumentException(CoderResult.unmappableForLength(bad));
        assert(uErr !is null && uErr.getMessage() == "Non-positive length");
    }
}
