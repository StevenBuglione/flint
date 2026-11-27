/*
 * Copyright (c) 1994, 2023, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/lang/Long.java
// Modified by the Flint authors: the static members as a zero-aggregate leaf. A boxed `Long` is a D `long` (R5),
// so `valueOf` and `decode` return the primitive. Parsing and formatting go through flint.java.internal.integers,
// without exceptions; the throwing and string-returning members are zero-parameter templates, so only a program
// that calls them links the `flint.java.lang` exception hierarchy or the GC array copy (S-132, S-150). The bit
// operations use core.bitop's intrinsics, and `compress`/`expand` a loop over the mask's set bits, where Java uses
// Hacker's Delight's branch-free forms; each returns the same value for every input. `TYPE`, `describeConstable`,
// `getLong`, the `CharSequence` overloads and the instance members are not ported here.

/// Java 21 `java.lang.Long`'s static members. Import from `flint.java.lang.long_` (R19: `long` is a D keyword).
module flint.java.lang.long_;

@safe:

/// Java's `Long` statics.
struct Long
{
    /// The smallest `long`, -2^63.
    enum long MIN_VALUE = long.min;
    /// The largest `long`, 2^63 - 1.
    enum long MAX_VALUE = long.max;
    /// The number of bits in a `long`.
    enum int SIZE = 64;
    /// The number of bytes in a `long`.
    enum int BYTES = SIZE / 8;

    /// Java's `Long.toString(long)`: the signed decimal text of `i`.
    static string toString()(long i) pure nothrow
    {
        import flint.java.internal.integers : javaIntText;

        return javaIntText(i);
    }

    /// Java's `Long.toString(long, radix)`: the signed text of `i` in `radix`, lower-case; radix 10 outside 2..36.
    static string toString()(long i, int radix) pure nothrow
    {
        import flint.java.internal.integers : javaRadixText;

        return javaRadixText(i, radix, false);
    }

    /// Java's `Long.toUnsignedString(long)`: the decimal text of `i` read as unsigned.
    static string toUnsignedString()(long i) pure nothrow
    {
        import flint.java.internal.integers : javaRadixText;

        return javaRadixText(i, 10, true);
    }

    /// Java's `Long.toUnsignedString(long, radix)`: the text of `i` read as unsigned; radix 10 outside 2..36.
    static string toUnsignedString()(long i, int radix) pure nothrow
    {
        import flint.java.internal.integers : javaRadixText;

        return javaRadixText(i, radix, true);
    }

    /// Java's `Long.toHexString`: the unsigned hexadecimal text of `i`, lower-case, without leading zeros.
    static string toHexString()(long i) pure nothrow
    {
        import flint.java.internal.integers : javaRadixText;

        return javaRadixText(i, 16, true);
    }

    /// Java's `Long.toOctalString`: the unsigned octal text of `i`, without leading zeros.
    static string toOctalString()(long i) pure nothrow
    {
        import flint.java.internal.integers : javaRadixText;

        return javaRadixText(i, 8, true);
    }

    /// Java's `Long.toBinaryString`: the unsigned binary text of `i`, without leading zeros.
    static string toBinaryString()(long i) pure nothrow
    {
        import flint.java.internal.integers : javaRadixText;

        return javaRadixText(i, 2, true);
    }

    /++
    Java's `Long.parseLong(s, radix)`. Digits are those of `Character.digit`, so any script's decimal digits and
    the fullwidth Latin letters count. Throws `NumberFormatException` with Java's message; a null `s` is Java's `""`.
    +/
    static long parseLong()(string s, int radix = 10)
    {
        import flint.java.internal.integers : IntParse, parseJavaLong, throwIntParse;

        long l;
        const status = parseJavaLong(s, radix, l);
        if (status != IntParse.ok)
            throwIntParse(status, s, radix);
        return l;
    }

    /++
    Java's `Long.parseUnsignedLong(s, radix)`: an optional `+`, then digits up to 2^64 - 1, which wraps to the
    negative `long`s. Throws `NumberFormatException` with Java's message, including the `Error at index` and
    `Bad digit at end` forms of text longer than 12 UTF-16 units; a null `s` is Java's `""`.
    +/
    static long parseUnsignedLong()(string s, int radix = 10)
    {
        import flint.java.internal.integers : IntParse, parseJavaUnsignedLong, throwIntParse;

        long l;
        size_t failure;
        const status = parseJavaUnsignedLong(s, radix, l, failure);
        if (status != IntParse.ok)
            throwIntParse(status, s, radix, failure);
        return l;
    }

    /// Java's `Long.valueOf(long)`, the boxing factory: the value itself (R5).
    static long valueOf(long l) pure nothrow @nogc
    {
        return l;
    }

    /// Java's `Long.valueOf(s, radix)`: `parseLong`, boxed (R5).
    static long valueOf()(string s, int radix = 10)
    {
        return parseLong(s, radix);
    }

    /++
    Java's `Long.decode(nm)`: an optional sign, then `0x`, `0X` or `#` for hexadecimal or a leading `0` for octal.
    Throws `NumberFormatException` with Java's message.
    +/
    static long decode()(string nm)
    {
        import flint.java.internal.integers : DecodeSite, IntParse, decodeJavaLong, throwIntDecode;

        long l;
        DecodeSite site;
        const status = decodeJavaLong(nm, l, site);
        if (status != IntParse.ok)
            throwIntDecode(status, nm, site);
        return l;
    }

    /// Java's `Long.hashCode(long)`: the two halves of `value` exclusive-or'ed.
    static int hashCode(long value) pure nothrow @nogc
    {
        return cast(int)(value ^ (cast(ulong) value >>> 32));
    }

    /// Java's `Long.compare`: -1, 0 or 1.
    static int compare(long x, long y) pure nothrow @nogc
    {
        return x < y ? -1 : (x == y ? 0 : 1);
    }

    /// Java's `Long.compareUnsigned`: `compare` of the values read as unsigned.
    static int compareUnsigned(long x, long y) pure nothrow @nogc
    {
        return compare(x + MIN_VALUE, y + MIN_VALUE);
    }

    /// Java's `Long.divideUnsigned`. Throws `ArithmeticException` for a zero divisor.
    static long divideUnsigned()(long dividend, long divisor) pure
    {
        import flint.java.internal.integers : unsignedQuotient;

        return cast(long) unsignedQuotient(cast(ulong) dividend, cast(ulong) divisor);
    }

    /// Java's `Long.remainderUnsigned`. Throws `ArithmeticException` for a zero divisor.
    static long remainderUnsigned()(long dividend, long divisor) pure
    {
        import flint.java.internal.integers : unsignedRemainder;

        return cast(long) unsignedRemainder(cast(ulong) dividend, cast(ulong) divisor);
    }

    /// Java's `Long.highestOneBit`: `i` with all but its highest set bit cleared, or 0.
    static long highestOneBit(long i) pure nothrow @nogc
    {
        return i == 0 ? 0 : cast(long)(0x8000_0000_0000_0000UL >>> numberOfLeadingZeros(i));
    }

    /// Java's `Long.lowestOneBit`: `i` with all but its lowest set bit cleared, or 0.
    static long lowestOneBit(long i) pure nothrow @nogc
    {
        return i & -i;
    }

    /// Java's `Long.numberOfLeadingZeros`: the zero bits above the highest set bit; 64 for 0.
    static int numberOfLeadingZeros(long i) pure nothrow @nogc
    {
        import core.bitop : bsr;

        return i == 0 ? 64 : 63 - bsr(cast(ulong) i);
    }

    /// Java's `Long.numberOfTrailingZeros`: the zero bits below the lowest set bit; 64 for 0.
    static int numberOfTrailingZeros(long i) pure nothrow @nogc
    {
        import core.bitop : bsf;

        return i == 0 ? 64 : bsf(cast(ulong) i);
    }

    /// Java's `Long.bitCount`: the number of set bits.
    static int bitCount(long i) pure nothrow @nogc
    {
        import core.bitop : popcnt;

        return popcnt(cast(ulong) i);
    }

    /// Java's `Long.rotateLeft`: only the low six bits of `distance` count, so a negative one rotates right.
    static long rotateLeft(long i, int distance) pure nothrow @nogc
    {
        const shift = distance & 63;
        return shift == 0 ? i : cast(long)((cast(ulong) i << shift) | (cast(ulong) i >>> (64 - shift)));
    }

    /// Java's `Long.rotateRight`: only the low six bits of `distance` count, so a negative one rotates left.
    static long rotateRight(long i, int distance) pure nothrow @nogc
    {
        return rotateLeft(i, -distance);
    }

    /// Java's `Long.reverse`: the 64 bits of `i` in reverse order.
    static long reverse(long i) pure nothrow @nogc
    {
        import core.bitop : bitswap;

        return cast(long) bitswap(cast(ulong) i);
    }

    /// Java's `Long.compress`: the bits of `i` under `mask`, packed into the low bits in order.
    static long compress(long i, long mask) pure nothrow @nogc
    {
        // Each set bit of the mask, lowest first, takes the next result bit. A template instance shared through
        // flint.java.internal.integers would link its parsers (S-150), so each leaf keeps its own loop.
        ulong result = 0;
        uint at;
        for (ulong m = mask; m != 0; m &= m - 1, at++)
            if (i & m & -m)
                result |= cast(ulong) 1 << at;
        return cast(long) result;
    }

    /// Java's `Long.expand`: the low bits of `i`, spread in order to the set bits of `mask`.
    static long expand(long i, long mask) pure nothrow @nogc
    {
        // Each set bit of the mask, lowest first, receives the next low bit of `i`.
        ulong result = 0;
        uint at;
        for (ulong m = mask; m != 0; m &= m - 1, at++)
            if ((cast(ulong) i >>> at) & 1)
                result |= m & -m;
        return cast(long) result;
    }

    /// Java's `Long.signum`: -1, 0 or 1.
    static int signum(long i) pure nothrow @nogc
    {
        return (i > 0) - (i < 0);
    }

    /// Java's `Long.reverseBytes`: the eight bytes of `i` in reverse order.
    static long reverseBytes(long i) pure nothrow @nogc
    {
        import core.bitop : bswap;

        return cast(long) bswap(cast(ulong) i);
    }

    /// Java's `Long.sum`: `a + b`, wrapping.
    static long sum(long a, long b) pure nothrow @nogc
    {
        return a + b;
    }

    /// Java's `Long.max`.
    static long max(long a, long b) pure nothrow @nogc
    {
        return a >= b ? a : b;
    }

    /// Java's `Long.min`.
    static long min(long a, long b) pure nothrow @nogc
    {
        return a <= b ? a : b;
    }
}
