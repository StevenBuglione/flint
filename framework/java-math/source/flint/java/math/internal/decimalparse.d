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
module flint.java.math.internal.decimalparse;

import flint.java.math.internal.radixparse : digitAt;

@safe:

package(flint.java.math):

/// Decimal metadata and the input byte range needed to materialize a large coefficient.
struct DecimalParts
{
    long compactValue;
    int scale;
    int precision;
    size_t coefficientStart;
    size_t coefficientEnd;
    bool isCompact;
    bool negative;
}

/// Validate the Java decimal grammar without allocating or retaining the input.
bool scanDecimal(scope const(char)[] text, out DecimalParts parts) pure nothrow @nogc
{
    if (text.length == 0)
        return false;

    const bool negative = text[0] == '-';
    const size_t start = negative || text[0] == '+' ? 1 : 0;
    size_t position = start;
    Coefficient coefficient;
    if (!readCoefficient(text, position, negative, coefficient))
        return false;

    int scale = coefficient.fractionDigits;
    if (position < text.length)
    {
        const char marker = text[position];
        if (marker != 'e' && marker != 'E')
            return false;
        if (!readScale(text[position + 1 .. $], coefficient.fractionDigits, scale))
            return false;
    }

    const ulong magnitude = coefficient.magnitude;
    parts.compactValue = coefficient.isCompact ? cast(long)(negative ? 0UL - magnitude : magnitude) : 0;
    parts.scale = scale;
    parts.precision = coefficient.precision ? coefficient.precision : 1;
    parts.coefficientStart = start;
    parts.coefficientEnd = position;
    parts.isCompact = coefficient.isCompact;
    parts.negative = negative && coefficient.precision != 0;
    return true;
}

private:

struct Coefficient
{
    ulong magnitude;
    int precision;
    int fractionDigits;
    bool isCompact = true;
}

bool readCoefficient(scope const(char)[] text, ref size_t at, bool negative, out Coefficient value) pure nothrow @nogc
{
    const ulong limit = cast(ulong) long.max + (negative ? 1 : 0);
    const int integerDigits = readDigits(text, at, limit, value);
    if (integerDigits < 0)
        return false;
    if (at < text.length && text[at] == '.')
    {
        ++at;
        value.fractionDigits = readDigits(text, at, limit, value);
        if (value.fractionDigits < 0)
            return false;
    }
    return integerDigits != 0 || value.fractionDigits != 0;
}

// Stop at a separator or invalid character, leaving the grammar check to the caller.
int readDigits(scope const(char)[] text, ref size_t at, ulong limit, ref Coefficient value) pure nothrow @nogc
{
    int count;
    while (at < text.length)
    {
        const size_t start = at;
        const int digit = digitAt(text, at, 10);
        if (digit < 0)
        {
            at = start;
            break;
        }
        if (count == int.max)
            return -1;
        ++count;
        if (value.precision || digit)
        {
            if (value.precision == int.max)
                return -1;
            ++value.precision;
        }
        if (value.isCompact)
        {
            const uint digitValue = cast(uint) digit;
            if (value.magnitude > (limit - digitValue) / 10)
                value.isCompact = false;
            else
                value.magnitude = value.magnitude * 10 + digitValue;
        }
    }
    return count;
}

bool readScale(scope const(char)[] exponent, int fractionDigits, out int scale) pure nothrow @nogc
{
    if (exponent.length == 0)
        return false;

    const bool negative = exponent[0] == '-';
    size_t position = negative || exponent[0] == '+' ? 1 : 0;
    if (position == exponent.length)
        return false;

    // Java bounds the resulting scale, so a positive exponent may exceed int.max.
    const ulong limit = negative ? int.max - fractionDigits : cast(long) fractionDigits - int.min;
    ulong magnitude;
    while (position < exponent.length)
    {
        const int digit = digitAt(exponent, position, 10);
        if (digit < 0 || cast(uint) digit > limit || magnitude > (limit - cast(uint) digit) / 10)
            return false;
        magnitude = magnitude * 10 + cast(uint) digit;
    }
    const long delta = cast(long) magnitude;
    scale = cast(int)(negative ? fractionDigits + delta : fractionDigits - delta);
    return true;
}
