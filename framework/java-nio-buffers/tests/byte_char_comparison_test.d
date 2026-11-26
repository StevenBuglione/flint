// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module byte_char_comparison_test;

import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.byteorder : ByteOrder;
import flint.java.nio.charbuffer : CharBuffer;

@safe:

@("Opposite byte orders and unaligned origins compare logical UTF-16 values")
unittest
{
    const wchar[5] data = [0x41, 0xD800, 0xDC00, 0xFFFF, 0xFFFE];
    auto words = CharBuffer.allocate(8).put(1, data[]).position(1).limit(6).mark();
    auto first = ByteBuffer.allocate(17).position(1).mark().order(ByteOrder.BIG_ENDIAN);
    auto big = first.asCharBuffer().put(2, data[]).position(2).limit(7).mark();
    auto little = ByteBuffer.allocate(15).position(3).order(ByteOrder.LITTLE_ENDIAN).asCharBuffer()
        .put(data[]).flip().mark().asReadOnlyBuffer();
    assert(words.equals(big) && big.equals(little) && little.equals(words));
    assert(words.hashCode() == big.hashCode() && big.hashCode() == little.hashCode());
    assert(big.mismatch(little) == -1 && little.compareTo(big) == 0);
    assert(!words.equals(first));

    big.put(3, cast(wchar) 0x007F);
    assert(words.compareTo(big) == 0xD800 - 0x007F);
    assert(big.compareTo(little) == 0x007F - 0xD800);
    assert(big.mismatch(words) == 1 && little.mismatch(big) == 1);
    assert(!words.equals(big) && !big.equals(little));
    assert(big.position() == 2 && big.reset().position() == 2);
    assert(little.position() == 0 && little.reset().position() == 0);
    assert(words.reset().position() == 1 && first.reset().position() == 1);
}
