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

/*
 * Portions Copyright IBM Corporation, 2001. All Rights Reserved.
 */

// Modified by the Flint authors.
// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Ported from openjdk 21.0.13: src/java.base/share/classes/java/math/BigDecimal.java
module flint.java.math.bigdecimal;

import flint.engine.aot.text : tryParseDouble, tryParseFloat;
import flint.java.lang : NumberFormatException;
import flint.java.lang.number : Number;
import flint.java.math.biginteger : BigInteger;
import flint.java.math.internal.decimalcoefficient : materializeCoefficient;
import flint.java.math.internal.decimalparse : DecimalParts, scanDecimal;

@safe:

/// An exact decimal represented as a signed coefficient times ten to the negative scale.
class BigDecimal : Number
{
    private long compact;
    private BigInteger wide;
    private int decimalScale;
    private int decimalPrecision;

    /// Parse a Java decimal string. A null text slice follows the empty-text path (R26).
    this(scope const(char)[] value)
    {
        DecimalParts parts;
        if (!scanDecimal(value, parts))
            throw new NumberFormatException("Invalid BigDecimal value");
        compact = parts.compactValue;
        if (!parts.isCompact)
            wide = materializeCoefficient(value, parts);
        decimalScale = parts.scale;
        decimalPrecision = parts.precision;
    }

    /// Return the number of decimal places. A negative scale denotes multiplication by a power of ten.
    int scale() const pure nothrow @nogc
    {
        return decimalScale;
    }

    /// Return the number of significant coefficient digits, including trailing zeros.
    int precision() const pure nothrow @nogc
    {
        return decimalPrecision;
    }

    /// Return the sign of the numeric value.
    int signum() const pure nothrow @nogc
    {
        if (wide !is null)
            return wide.signum();
        return (compact > 0) - (compact < 0);
    }

    /// Return the signed integer coefficient before applying the scale.
    BigInteger unscaledValue() pure nothrow
    {
        return wide !is null ? wide : BigInteger.valueOf(compact);
    }

    /// Return Java's canonical decimal representation, retaining the scale.
    override string toString() const pure nothrow
    {
        if (wide !is null)
        {
            const digits = wide.toString();
            if (decimalScale == 0)
                return digits;
            return renderDecimal(digits, decimalScale);
        }
        char[20] buffer;
        const size_t start = writeSigned(compact, buffer[]);
        return renderDecimal(buffer[start .. $], decimalScale);
    }

    /// Discard the fraction and return the low 32 bits.
    override int intValue()
    {
        return cast(int) longValue();
    }

    /// Discard the fraction and return the low 64 bits.
    override long longValue()
    {
        if (decimalScale >= decimalPrecision || decimalScale <= -64)
            return 0;
        if (decimalScale <= 0)
        {
            const long coefficient = wide is null ? compact : wide.longValue();
            if (decimalScale == 0)
                return coefficient;
            return cast(long)(cast(ulong) coefficient * powerOfTen(cast(uint)-decimalScale));
        }
        if (wide is null)
            return compact / cast(long) powerOfTen(cast(uint) decimalScale);
        return wide.divide(BigInteger.valueOf(10).pow(decimalScale)).longValue();
    }

    /// Round directly to binary32.
    override float floatValue() const
    {
        return cast(float) binaryValue(true);
    }

    /// Round directly to binary64.
    override double doubleValue() const
    {
        return binaryValue(false);
    }

    private double binaryValue(bool single) const
    {
        const int sign = signum();
        if (sign == 0)
            return 0;
        if (decimalScale == 0)
        {
            if (wide !is null)
                return single ? cast(double) wide.floatValue() : wide.doubleValue();
            return single ? cast(double) cast(float) compact : cast(double) compact;
        }
        const long exponent = cast(long) decimalPrecision - decimalScale - 1;
        if (exponent > (single ? 38 : 308))
            return sign < 0 ? -double.infinity : double.infinity;
        if (exponent < (single ? -46 : -324))
            return sign < 0 ? -0.0 : 0.0;
        return parseScaledValue(single);
    }

    private double parseScaledValue(bool single) const
    {
        // A signed long, the exponent marker, and the signed magnitude of any int scale.
        char[32] text;
        const size_t marker = writeSigned(-cast(long) decimalScale, text[]) - 1;
        text[marker] = 'E';
        if (wide !is null)
            return readBinary(wide.toString() ~ text[marker .. $], single);
        const size_t start = writeSigned(compact, text[0 .. marker]);
        return readBinary(text[start .. $], single);
    }
}

private:

// The coefficient has at least one digit and may include a leading minus.
char[] renderDecimal(scope const(char)[] digits, int scale) pure nothrow
{
    if (scale == 0)
        return digits.dup;

    const size_t sign = digits[0] == '-';
    const long adjusted = cast(long)(digits.length - sign) - scale - 1;
    if (scale > 0 && adjusted >= -6)
    {
        if (adjusted >= 0)
        {
            const size_t point = sign + cast(size_t) adjusted + 1;
            auto text = new char[digits.length + 1];
            text[0 .. point] = digits[0 .. point];
            text[point] = '.';
            text[point + 1 .. $] = digits[point .. $];
            return text;
        }
        const size_t coefficient = sign + 2 + cast(size_t)(-adjusted - 1);
        auto text = new char[coefficient + digits.length - sign];
        text[0 .. sign] = digits[0 .. sign];
        text[sign .. sign + 2] = "0.";
        text[sign + 2 .. coefficient] = '0';
        text[coefficient .. $] = digits[sign .. $];
        return text;
    }

    char[21] exponent;
    size_t start = writeSigned(adjusted, exponent[]);
    if (adjusted > 0)
        exponent[--start] = '+';
    const size_t firstDigitEnd = sign + 1;
    const bool fraction = digits.length != firstDigitEnd;
    const size_t marker = digits.length + fraction;
    auto text = new char[marker + 1 + exponent.length - start];
    text[0 .. firstDigitEnd] = digits[0 .. firstDigitEnd];
    if (fraction)
    {
        text[firstDigitEnd] = '.';
        text[firstDigitEnd + 1 .. marker] = digits[firstDigitEnd .. $];
    }
    text[marker] = 'E';
    text[marker + 1 .. $] = exponent[start .. $];
    return text;
}

// Exponents at least 64 yield zero modulo 2^64. The caller excludes them.
ulong powerOfTen(uint exponent) pure nothrow @nogc
{
    ulong power = 1;
    ulong factor = 10;
    while (exponent)
    {
        if (exponent & 1)
            power *= factor;
        factor *= factor;
        exponent >>= 1;
    }
    return power;
}

size_t writeSigned(long value, scope char[] buffer) pure nothrow @nogc
{
    ulong magnitude = value < 0 ? 0UL - cast(ulong) value : cast(ulong) value;
    size_t start = buffer.length;
    do
    {
        buffer[--start] = cast(char)('0' + magnitude % 10);
        magnitude /= 10;
    }
    while (magnitude);
    if (value < 0)
        buffer[--start] = '-';
    return start;
}

// The text is internally generated decimal syntax. A failed conversion means overflow.
double readBinary(scope const(char)[] text, bool single) pure nothrow
{
    if (single)
    {
        const result = tryParseFloat(text);
        if (result.ok)
            return result.value;
    }
    else
    {
        const result = tryParseDouble(text);
        if (result.ok)
            return result.value;
    }
    return text[0] == '-' ? -double.infinity : double.infinity;
}
