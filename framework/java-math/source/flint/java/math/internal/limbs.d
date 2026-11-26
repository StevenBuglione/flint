/*
 *  Licensed to the Apache Software Foundation (ASF) under one or more
 *  contributor license agreements.  See the NOTICE file distributed with
 *  this work for additional information regarding copyright ownership.
 *  The ASF licenses this file to You under the Apache License, Version 2.0
 *  (the "License"); you may not use this file except in compliance with
 *  the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 *
 *  Copyright 2006, 2010 The Apache Software Foundation.
 *  Ported from harmony 6.0M3, classlib/modules/math/src/main/java/java/math/Elementary.java
 *  Modified by the Flint authors.
 */
module flint.java.math.internal.limbs;

import core.bitop : bsr;

@safe:

package(flint.java.math):

/// The length of the magnitude after removing zero limbs from its most significant end.
size_t significantLimbs(scope const(uint)[] words) pure nothrow @nogc
{
    size_t length = words.length;
    while (length && words[length - 1] == 0)
        --length;
    return length;
}

/// The bit length of a normalized magnitude.
size_t magnitudeBitLength(scope const(uint)[] words) pure nothrow @nogc
{
    return words.length ? words.length * 32 - 31 + bsr(words[$ - 1]) : 0;
}

/// Compare normalized unsigned magnitudes, with the least significant limb at index zero.
int compareLimbs(scope const(uint)[] left, scope const(uint)[] right) pure nothrow @nogc
{
    if (left.length != right.length)
        return left.length < right.length ? -1 : 1;
    foreach_reverse (i; 0 .. left.length)
        if (left[i] != right[i])
            return left[i] < right[i] ? -1 : 1;
    return 0;
}

/// Sum two magnitudes. The left input is at least as long as the right.
void addLimbs(scope uint[] sum, scope const(uint)[] left, scope const(uint)[] right) pure nothrow @nogc
{
    ulong carry;
    foreach (i; 0 .. right.length)
    {
        carry += cast(ulong) left[i] + right[i];
        sum[i] = cast(uint) carry;
        carry >>= 32;
    }
    foreach (i; right.length .. left.length)
    {
        carry += left[i];
        sum[i] = cast(uint) carry;
        carry >>= 32;
    }
    sum[left.length] = cast(uint) carry;
}

/// Subtract two magnitudes. The left input is at least as large as the right.
void subtractLimbs(scope uint[] difference, scope const(uint)[] left, scope const(uint)[] right) pure nothrow @nogc
{
    long borrow;
    foreach (i; 0 .. right.length)
    {
        borrow += cast(long) left[i] - right[i];
        difference[i] = cast(uint) borrow;
        borrow >>= 32;
    }
    foreach (i; right.length .. left.length)
    {
        borrow += left[i];
        difference[i] = cast(uint) borrow;
        borrow >>= 32;
    }
}

/// Remove leading zero bytes or redundant sign extension before allocating limbs.
const(byte)[] significantBytes(return scope const(byte)[] bytes, bool negative) pure nothrow @nogc
{
    if (!negative)
    {
        while (bytes.length && bytes[0] == 0)
            bytes = bytes[1 .. $];
    }
    else
    {
        while (bytes.length > 1 && bytes[0] == -1 && bytes[1] < 0)
            bytes = bytes[1 .. $];
    }
    return bytes;
}

/// Read big-endian magnitude bytes or recover the magnitude of negative two's-complement bytes.
void loadLimbs(scope uint[] words, scope const(byte)[] bytes, bool negative) pure nothrow @nogc
{
    uint carry = negative;
    uint mask = negative ? 255 : 0;
    foreach (i; 0 .. bytes.length)
    {
        const uint digit = (cast(ubyte) bytes[$ - 1 - i] ^ mask) + carry;
        words[i / 4] |= (digit & 255) << ((i % 4) * 8);
        carry = digit >> 8;
    }
}

/// For negative values, this limb is the last to receive a carry in the two's-complement encoding.
size_t firstNonzeroLimb(scope const(uint)[] words) pure nothrow @nogc
{
    size_t index;
    while (words[index] == 0)
        ++index;
    return index;
}

/// Length of the shortest signed encoding, including a sign bit. For a negative value count bits in magnitude - 1.
size_t signedLength(scope const(uint)[] words, bool negative, size_t firstNonzero) pure nothrow @nogc
{
    if (!words.length)
        return 1;
    size_t highIndex = words.length;
    --highIndex;
    const uint high = words[highIndex] - (negative && firstNonzero == highIndex ? 1 : 0);
    return highIndex * 4 + (high ? (bsr(high) + 1) / 8 : 0) + 1;
}

/// Write a big-endian, signed encoding of the magnitude into a destination of signedLength bytes.
void storeSignedBytes(scope byte[] bytes, scope const(uint)[] words, bool negative, size_t first) pure nothrow @nogc
{
    foreach (i; 0 .. bytes.length)
    {
        const size_t index = i / 4;
        uint word = index < words.length ? words[index] : 0;
        if (negative && index >= first)
            word = index == first ? 0U - word : ~word;
        bytes[$ - 1 - i] = cast(byte)(word >> ((i % 4) * 8));
    }
}
