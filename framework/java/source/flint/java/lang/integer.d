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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/lang/Integer.java
// Modified by the Flint authors: the static members as a zero-aggregate leaf. A boxed `Integer` is a D `int` (R5),
// so `valueOf` and `decode` return the primitive. Parsing and formatting go through flint.java.internal.integers,
// without exceptions; the throwing and string-returning members are zero-parameter templates, so only a program
// that calls them links the `flint.java.lang` exception hierarchy or the GC array copy (S-132, S-150). The bit
// operations use core.bitop's intrinsics, and `compress`/`expand` a loop over the mask's set bits, where Java uses
// Hacker's Delight's branch-free forms; each returns the same value for every input. `TYPE`, `describeConstable`,
// `getInteger`, the `CharSequence` overloads and the instance members are not ported here.

/// Java 21 `java.lang.Integer`'s static members.
module flint.java.lang.integer;

@safe:

/// Java's `Integer` statics.
struct Integer
{
    /// The smallest `int`, -2^31.
    enum int MIN_VALUE = int.min;
    /// The largest `int`, 2^31 - 1.
    enum int MAX_VALUE = int.max;
    /// The number of bits in an `int`.
    enum int SIZE = 32;
    /// The number of bytes in an `int`.
    enum int BYTES = SIZE / 8;

    /// Java's `Integer.toString(int)`: the signed decimal text of `i`.
    static string toString()(int i) pure nothrow
    {
        import flint.java.internal.integers : javaIntText;

        return javaIntText(i);
    }

    /// Java's `Integer.toString(int, radix)`: the signed text of `i` in `radix`, lower-case; radix 10 outside 2..36.
    static string toString()(int i, int radix) pure nothrow
    {
        import flint.java.internal.integers : javaRadixText;

        return javaRadixText(i, radix, false);
    }

    /// Java's `Integer.toUnsignedString(int)`: the decimal text of `i` read as unsigned.
    static string toUnsignedString()(int i) pure nothrow
    {
        import flint.java.internal.integers : javaIntText;

        return javaIntText(toUnsignedLong(i));
    }

    /// Java's `Integer.toUnsignedString(int, radix)`: the text of `i` read as unsigned; radix 10 outside 2..36.
    static string toUnsignedString()(int i, int radix) pure nothrow
    {
        import flint.java.internal.integers : javaRadixText;

        return javaRadixText(toUnsignedLong(i), radix, false);
    }

    /// Java's `Integer.toHexString`: the unsigned hexadecimal text of `i`, lower-case, without leading zeros.
    static string toHexString()(int i) pure nothrow
    {
        import flint.java.internal.integers : javaRadixText;

        return javaRadixText(toUnsignedLong(i), 16, true);
    }

    /// Java's `Integer.toOctalString`: the unsigned octal text of `i`, without leading zeros.
    static string toOctalString()(int i) pure nothrow
    {
        import flint.java.internal.integers : javaRadixText;

        return javaRadixText(toUnsignedLong(i), 8, true);
    }

    /// Java's `Integer.toBinaryString`: the unsigned binary text of `i`, without leading zeros.
    static string toBinaryString()(int i) pure nothrow
    {
        import flint.java.internal.integers : javaRadixText;

        return javaRadixText(toUnsignedLong(i), 2, true);
    }

    /++
    Java's `Integer.parseInt(s, radix)`. Digits are those of `Character.digit`, so any script's decimal digits and
    the fullwidth Latin letters count. Throws `NumberFormatException` with Java's message; a null `s` is Java's `""`.
    +/
    static int parseInt()(string s, int radix = 10)
    {
        import flint.java.internal.integers : IntParse, parseJavaInt, throwIntParse;

        int i;
        const status = parseJavaInt(s, radix, i);
        if (status != IntParse.ok)
            throwIntParse(status, s, radix);
        return i;
    }

    /++
    Java's `Integer.parseUnsignedInt(s, radix)`: an optional `+`, then digits up to 2^32 - 1, which wraps to the
    negative `int`s. Throws `NumberFormatException` with Java's message; a null `s` is Java's `""`.
    +/
    static int parseUnsignedInt()(string s, int radix = 10)
    {
        import flint.java.internal.integers : IntParse, parseJavaUnsignedInt, throwIntParse;

        int i;
        const status = parseJavaUnsignedInt(s, radix, i);
        if (status != IntParse.ok)
            throwIntParse(status, s, radix);
        return i;
    }

    /// Java's `Integer.valueOf(int)`, the boxing factory: the value itself (R5).
    static int valueOf(int i) pure nothrow @nogc
    {
        return i;
    }

    /// Java's `Integer.valueOf(s, radix)`: `parseInt`, boxed (R5).
    static int valueOf()(string s, int radix = 10)
    {
        return parseInt(s, radix);
    }

    /++
    Java's `Integer.decode(nm)`: an optional sign, then `0x`, `0X` or `#` for hexadecimal or a leading `0` for
    octal. Throws `NumberFormatException` with Java's message.
    +/
    static int decode()(string nm)
    {
        import flint.java.internal.integers : DecodeSite, IntParse, decodeJavaInt, throwIntDecode;

        int i;
        DecodeSite site;
        const status = decodeJavaInt(nm, i, site);
        if (status != IntParse.ok)
            throwIntDecode(status, nm, site);
        return i;
    }

    /// Java's `Integer.hashCode(int)`: the value.
    static int hashCode(int value) pure nothrow @nogc
    {
        return value;
    }

    /// Java's `Integer.compare`: -1, 0 or 1.
    static int compare(int x, int y) pure nothrow @nogc
    {
        return x < y ? -1 : (x == y ? 0 : 1);
    }

    /// Java's `Integer.compareUnsigned`: `compare` of the values read as unsigned.
    static int compareUnsigned(int x, int y) pure nothrow @nogc
    {
        return compare(x + MIN_VALUE, y + MIN_VALUE);
    }

    /// Java's `Integer.toUnsignedLong`: `x` zero-extended.
    static long toUnsignedLong(int x) pure nothrow @nogc
    {
        return cast(uint) x;
    }

    /// Java's `Integer.divideUnsigned`. Throws `ArithmeticException` for a zero divisor.
    static int divideUnsigned()(int dividend, int divisor) pure
    {
        import flint.java.internal.integers : unsignedQuotient;

        return cast(int) unsignedQuotient(cast(uint) dividend, cast(uint) divisor);
    }

    /// Java's `Integer.remainderUnsigned`. Throws `ArithmeticException` for a zero divisor.
    static int remainderUnsigned()(int dividend, int divisor) pure
    {
        import flint.java.internal.integers : unsignedRemainder;

        return cast(int) unsignedRemainder(cast(uint) dividend, cast(uint) divisor);
    }

    /// Java's `Integer.highestOneBit`: `i` with all but its highest set bit cleared, or 0.
    static int highestOneBit(int i) pure nothrow @nogc
    {
        return i == 0 ? 0 : cast(int)(0x8000_0000u >>> numberOfLeadingZeros(i));
    }

    /// Java's `Integer.lowestOneBit`: `i` with all but its lowest set bit cleared, or 0.
    static int lowestOneBit(int i) pure nothrow @nogc
    {
        return i & -i;
    }

    /// Java's `Integer.numberOfLeadingZeros`: the zero bits above the highest set bit; 32 for 0.
    static int numberOfLeadingZeros(int i) pure nothrow @nogc
    {
        import core.bitop : bsr;

        return i == 0 ? 32 : 31 - bsr(cast(uint) i);
    }

    /// Java's `Integer.numberOfTrailingZeros`: the zero bits below the lowest set bit; 32 for 0.
    static int numberOfTrailingZeros(int i) pure nothrow @nogc
    {
        import core.bitop : bsf;

        return i == 0 ? 32 : bsf(cast(uint) i);
    }

    /// Java's `Integer.bitCount`: the number of set bits.
    static int bitCount(int i) pure nothrow @nogc
    {
        import core.bitop : popcnt;

        return popcnt(cast(uint) i);
    }

    /// Java's `Integer.rotateLeft`: only the low five bits of `distance` count, so a negative one rotates right.
    static int rotateLeft(int i, int distance) pure nothrow @nogc
    {
        const shift = distance & 31;
        return shift == 0 ? i : cast(int)((cast(uint) i << shift) | (cast(uint) i >>> (32 - shift)));
    }

    /// Java's `Integer.rotateRight`: only the low five bits of `distance` count, so a negative one rotates left.
    static int rotateRight(int i, int distance) pure nothrow @nogc
    {
        return rotateLeft(i, -distance);
    }

    /// Java's `Integer.reverse`: the 32 bits of `i` in reverse order.
    static int reverse(int i) pure nothrow @nogc
    {
        import core.bitop : bitswap;

        return cast(int) bitswap(cast(uint) i);
    }

    /// Java's `Integer.compress`: the bits of `i` under `mask`, packed into the low bits in order.
    static int compress(int i, int mask) pure nothrow @nogc
    {
        // Each set bit of the mask, lowest first, takes the next result bit. A template instance shared through
        // flint.java.internal.integers would link its parsers (S-150), so each leaf keeps its own loop.
        uint result = 0;
        uint at;
        for (uint m = mask; m != 0; m &= m - 1, at++)
            if (i & m & -m)
                result |= cast(uint) 1 << at;
        return cast(int) result;
    }

    /// Java's `Integer.expand`: the low bits of `i`, spread in order to the set bits of `mask`.
    static int expand(int i, int mask) pure nothrow @nogc
    {
        // Each set bit of the mask, lowest first, receives the next low bit of `i`.
        uint result = 0;
        uint at;
        for (uint m = mask; m != 0; m &= m - 1, at++)
            if ((cast(uint) i >>> at) & 1)
                result |= m & -m;
        return cast(int) result;
    }

    /// Java's `Integer.signum`: -1, 0 or 1.
    static int signum(int i) pure nothrow @nogc
    {
        return (i > 0) - (i < 0);
    }

    /// Java's `Integer.reverseBytes`: the four bytes of `i` in reverse order.
    static int reverseBytes(int i) pure nothrow @nogc
    {
        import core.bitop : bswap;

        return cast(int) bswap(cast(uint) i);
    }

    /// Java's `Integer.sum`: `a + b`, wrapping.
    static int sum(int a, int b) pure nothrow @nogc
    {
        return a + b;
    }

    /// Java's `Integer.max`.
    static int max(int a, int b) pure nothrow @nogc
    {
        return a >= b ? a : b;
    }

    /// Java's `Integer.min`.
    static int min(int a, int b) pure nothrow @nogc
    {
        return a <= b ? a : b;
    }
}
