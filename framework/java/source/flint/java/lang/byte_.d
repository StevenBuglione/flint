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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/lang/Byte.java
// Modified by the Flint authors: the static members as a zero-aggregate leaf. A boxed `Byte` is a D `byte` (R5), so
// `valueOf` and `decode` return the primitive. Parsing goes through flint.java.internal.integers, Java's
// `Integer.parseInt` and `Integer.decode` without exceptions; the throwing members are zero-parameter templates,
// so only a program that calls them links the `flint.java.lang` exception hierarchy (S-132). `TYPE`,
// `describeConstable` and the instance members are not ported here.

/// Java 21 `java.lang.Byte`'s static members. Import from `flint.java.lang.byte_` (R19: `byte` is a D keyword).
module flint.java.lang.byte_;

@safe:

/// Java's `Byte` statics.
struct Byte
{
    /// The smallest `byte`, -128.
    enum byte MIN_VALUE = -128;
    /// The largest `byte`, 127.
    enum byte MAX_VALUE = 127;
    /// The number of bits in a `byte`.
    enum int SIZE = 8;
    /// The number of bytes in a `byte`.
    enum int BYTES = SIZE / 8;

    /// Java's `Byte.toString(byte)`: the decimal text of `b`, as `Integer.toString` writes it.
    static string toString()(byte b) pure nothrow
    {
        import flint.java.internal.integers : javaIntText;

        return javaIntText(b);
    }

    /// Java's `Byte.valueOf(byte)`, the boxing factory: the value itself (R5).
    static byte valueOf(byte b) pure nothrow @nogc
    {
        return b;
    }

    /++
    Java's `Byte.parseByte(s, radix)`: `Integer.parseInt(s, radix)`, then a range check. Digits are those of
    `Character.digit`, so any script's decimal digits and the fullwidth Latin letters count. Throws
    `NumberFormatException` with Java's message; a null `s` is Java's `""`.
    +/
    static byte parseByte()(string s, int radix = 10)
    {
        import flint.java.internal.integers : IntParse, parseJavaInt, throwIntParse, throwParseRange;

        int i;
        const status = parseJavaInt(s, radix, i);
        if (status != IntParse.ok)
            throwIntParse(status, s, radix);
        if (i < MIN_VALUE || i > MAX_VALUE)
            throwParseRange(s, radix);
        return cast(byte) i;
    }

    /// Java's `Byte.valueOf(s, radix)`: `parseByte`, boxed (R5).
    static byte valueOf()(string s, int radix = 10)
    {
        return parseByte(s, radix);
    }

    /++
    Java's `Byte.decode(nm)`: `Integer.decode(nm)`, then a range check. Accepts an optional sign, then `0x`, `0X`
    or `#` for hexadecimal or a leading `0` for octal. Throws `NumberFormatException` with Java's message.
    +/
    static byte decode()(string nm)
    {
        import flint.java.internal.integers : DecodeSite, IntParse, decodeJavaInt, throwDecodeRange, throwIntDecode;

        int i;
        DecodeSite site;
        const status = decodeJavaInt(nm, i, site);
        if (status != IntParse.ok)
            throwIntDecode(status, nm, site);
        if (i < MIN_VALUE || i > MAX_VALUE)
            throwDecodeRange(i, nm);
        return cast(byte) i;
    }

    /// Java's `Byte.hashCode(byte)`: the value as an `int`.
    static int hashCode(byte value) pure nothrow @nogc
    {
        return value;
    }

    /// Java's `Byte.compare`: `x - y`.
    static int compare(byte x, byte y) pure nothrow @nogc
    {
        return x - y;
    }

    /// Java's `Byte.compareUnsigned`: the difference of the unsigned values.
    static int compareUnsigned(byte x, byte y) pure nothrow @nogc
    {
        return toUnsignedInt(x) - toUnsignedInt(y);
    }

    /// Java's `Byte.toUnsignedInt`: the low 8 bits of `x`, zero-extended.
    static int toUnsignedInt(byte x) pure nothrow @nogc
    {
        return x & 0xff;
    }

    /// Java's `Byte.toUnsignedLong`: the low 8 bits of `x`, zero-extended.
    static long toUnsignedLong(byte x) pure nothrow @nogc
    {
        return x & 0xffL;
    }
}
