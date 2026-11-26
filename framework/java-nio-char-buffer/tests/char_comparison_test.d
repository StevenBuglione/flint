// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module char_comparison_test;

import flint.java.lang : Comparable, NullPointerException;
import flint.java.nio.charbuffer : CharBuffer;
import std.exception : assertThrown;

@safe:

@("Character buffers compare only remaining units, including prefixes and empty windows")
unittest
{
    const wchar[5] data = [0x41, 0xD800, 0xDC00, 0xFFFF, 0xFFFE];
    auto left = CharBuffer.allocate(8).put(1, data[]).position(1).limit(6).mark();
    auto right = CharBuffer.wrap(data[].dup).mark().asReadOnlyBuffer();
    Comparable!CharBuffer comparable = left;
    assert(comparable.compareTo(right) == 0 && left.mismatch(right) == -1);
    assert(left.equals(right) && right.equals(left) && left == right);
    enum int expectedHash = -1_865_664_129;
    assert(left.hashCode() == expectedHash && left.hashCode() == right.hashCode());
    assert(left.toHash() == cast(uint) expectedHash);
    assert(left.equals(left) && !left.equals(null) && !left.equals(new Object));

    auto prefix = right.duplicate().limit(3);
    assert(left.compareTo(prefix) == 2 && prefix.compareTo(left) == -2);
    assert(left.mismatch(prefix) == 3 && prefix.mismatch(left) == 3);
    assert(!left.equals(prefix) && left > prefix);

    auto empty = CharBuffer.allocate(0);
    auto exhausted = right.duplicate().position(5);
    assert(empty.equals(exhausted) && empty.mismatch(exhausted) == -1);
    assert(empty.hashCode() == 1 && empty.compareTo(left) == -5 && empty.mismatch(left) == 0);
    assertThrown!NullPointerException(left.compareTo(null));
    assertThrown!NullPointerException(left.mismatch(null));
    assert(left.position() == 1 && left.reset().position() == 1);
    assert(prefix.position() == 0 && prefix.reset().position() == 0);
    assert(right.position() == 0 && right.reset().position() == 0);
}
