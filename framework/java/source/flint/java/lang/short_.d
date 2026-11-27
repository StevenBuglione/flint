/*
 * Copyright (c) 1996, 2023, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/lang/Short.java
// Modified by the Flint authors: the static members as a zero-aggregate leaf. A boxed `Short` is a D `short` (R5), so
// `valueOf` and `decode` return the primitive. Parsing goes through flint.java.internal.integers, Java's
// `Integer.parseInt` and `Integer.decode` without exceptions; the throwing members are zero-parameter templates,
// so only a program that calls them links the `flint.java.lang` exception hierarchy (S-132). `TYPE`,
// `describeConstable` and the instance members are not ported here.

/// Java 21 `java.lang.Short`'s static members. Import from `flint.java.lang.short_` (R19: `short` is a D keyword).
module flint.java.lang.short_;

@safe:

/// Java's `Short` statics.
struct Short
{
    /// The smallest `short`, -32,768.
    enum short MIN_VALUE = -32_768;
    /// The largest `short`, 32,767.
    enum short MAX_VALUE = 32_767;
    /// The number of bits in a `short`.
    enum int SIZE = 16;
    /// The number of bytes in a `short`.
    enum int BYTES = SIZE / 8;

    /// Java's `Short.toString(short)`: the decimal text of `s`, as `Integer.toString` writes it.
    static string toString()(short s) pure nothrow
    {
        import flint.java.internal.integers : javaIntText;

        return javaIntText(s);
    }

    /// Java's `Short.valueOf(short)`, the boxing factory: the value itself (R5).
    static short valueOf(short s) pure nothrow @nogc
    {
        return s;
    }

    /++
    Java's `Short.parseShort(s, radix)`: `Integer.parseInt(s, radix)`, then a range check. Digits are those of
    `Character.digit`, so any script's decimal digits and the fullwidth Latin letters count. Throws
    `NumberFormatException` with Java's message; a null `s` is Java's `""`.
    +/
    static short parseShort()(string s, int radix = 10)
    {
        import flint.java.internal.integers : IntParse, parseJavaInt, throwIntParse, throwParseRange;

        int i;
        const status = parseJavaInt(s, radix, i);
        if (status != IntParse.ok)
            throwIntParse(status, s, radix);
        if (i < MIN_VALUE || i > MAX_VALUE)
            throwParseRange(s, radix);
        return cast(short) i;
    }

    /// Java's `Short.valueOf(s, radix)`: `parseShort`, boxed (R5).
    static short valueOf()(string s, int radix = 10)
    {
        return parseShort(s, radix);
    }

    /++
    Java's `Short.decode(nm)`: `Integer.decode(nm)`, then a range check. Accepts an optional sign, then `0x`, `0X`
    or `#` for hexadecimal or a leading `0` for octal. Throws `NumberFormatException` with Java's message.
    +/
    static short decode()(string nm)
    {
        import flint.java.internal.integers : DecodeSite, IntParse, decodeJavaInt, throwDecodeRange, throwIntDecode;

        int i;
        DecodeSite site;
        const status = decodeJavaInt(nm, i, site);
        if (status != IntParse.ok)
            throwIntDecode(status, nm, site);
        if (i < MIN_VALUE || i > MAX_VALUE)
            throwDecodeRange(i, nm);
        return cast(short) i;
    }

    /// Java's `Short.hashCode(short)`: the value as an `int`.
    static int hashCode(short value) pure nothrow @nogc
    {
        return value;
    }

    /// Java's `Short.compare`: `x - y`.
    static int compare(short x, short y) pure nothrow @nogc
    {
        return x - y;
    }

    /// Java's `Short.compareUnsigned`: the difference of the unsigned values.
    static int compareUnsigned(short x, short y) pure nothrow @nogc
    {
        return toUnsignedInt(x) - toUnsignedInt(y);
    }

    /// Java's `Short.toUnsignedInt`: the low 16 bits of `x`, zero-extended.
    static int toUnsignedInt(short x) pure nothrow @nogc
    {
        return x & 0xffff;
    }

    /// Java's `Short.toUnsignedLong`: the low 16 bits of `x`, zero-extended.
    static long toUnsignedLong(short x) pure nothrow @nogc
    {
        return x & 0xffffL;
    }

    /// Java's `Short.reverseBytes`: the two bytes of `i` swapped.
    static short reverseBytes(short i) pure nothrow @nogc
    {
        return cast(short)(((i & 0xFF00) >> 8) | (i << 8));
    }
}
