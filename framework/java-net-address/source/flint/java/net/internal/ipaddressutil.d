/*
 * Copyright (c) 2004, 2022, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13:
//   src/java.base/share/classes/sun/net/util/IPAddressUtil.java (textToNumericFormatV4, isBsdParsableV4,
//   textToNumericFormatV6, convertFromIPv4MappedAddress, parseAsciiDigit)
//   src/java.base/share/classes/java/net/InetAddress.java (checkNumericZone)
// Modified by the Flint authors.

/++
IP address literal parsing for `InetAddress.getAllByName`, with `jdk.net.allowAmbiguousIPAddressLiterals` at its
default `false`: digits are ASCII only, and the caller rejects a literal that only the BSD rules accept.
+/
module flint.java.net.internal.ipaddressutil;

@safe:

package(flint.java.net):

enum INADDR4SZ = 4;
enum INADDR16SZ = 16;
private enum INT16SZ = 2;

/++
Java's `textToNumericFormatV4`: the 1- to 4-part decimal IPv4 forms. On success fills `res` and returns `true`;
otherwise returns `false`, as Java returns `null`.
+/
bool textToNumericFormatV4(scope const(char)[] src, ref ubyte[INADDR4SZ] res) pure nothrow @nogc
{
    res = 0;
    if (src.length == 0 || src.length > 15)
        return false;
    // At most 15 digits, so the value cannot overflow.
    long tmpValue;
    int currByte;
    bool newOctet = true;
    foreach (c; src)
    {
        if (c == '.')
        {
            if (newOctet || tmpValue > 0xff || currByte == 3)
                return false;
            res[currByte++] = cast(ubyte) tmpValue;
            tmpValue = 0;
            newOctet = true;
        }
        else
        {
            const digit = parseAsciiDigit(c, DECIMAL);
            if (digit < 0)
                return false;
            tmpValue = tmpValue * 10 + digit;
            newOctet = false;
        }
    }
    if (newOctet || tmpValue >= (1L << ((4 - currByte) * 8)))
        return false;
    // The last part fills the remaining bytes, as Java's fall-through switch does.
    foreach (i; currByte .. INADDR4SZ)
        res[i] = cast(ubyte)(tmpValue >> ((3 - i) * 8));
    return true;
}

/// Java's `isBsdParsableV4`: whether `input` parses as an IPv4 literal under BSD rules (hex, octal and decimal parts).
bool isBsdParsableV4(scope const(char)[] input) pure nothrow @nogc
{
    if (input.length == 0 || parseAsciiDigit(input[0], DECIMAL) == -1)
        return false;
    const lastSymbol = input[$ - 1];
    if (lastSymbol == '.' || parseAsciiDigit(lastSymbol, HEXADECIMAL) == -1)
        return false;
    static immutable int[3] supportedRadixes = [HEXADECIMAL, OCTAL, DECIMAL];
    size_t position;
    int fieldNumber;
    while (position < input.length)
    {
        long fieldValue = -1;
        foreach (radix; supportedRadixes)
        {
            fieldValue = parseV4FieldBsd(radix, input, position, fieldNumber);
            if (fieldValue >= 0)
            {
                fieldNumber++;
                break;
            }
            else if (fieldValue == TERMINAL_PARSE_ERROR)
                return false;
        }
        if (fieldValue < 0)
            return false;
    }
    return true;
}

/++
Java's `textToNumericFormatV6`, followed by `convertFromIPv4MappedAddress`: anything after a `%` is ignored. Returns
16 with the address in `dst`, 4 with an IPv4-mapped address's IPv4 part in `dst[0 .. 4]`, or 0 where Java returns
`null`.
+/
size_t textToNumericFormatV6(scope const(char)[] src, ref ubyte[INADDR16SZ] dst) pure nothrow @nogc
{
    dst = 0;
    // Shortest valid string is "::", hence at least 2 chars
    if (src.length < 2)
        return 0;
    const pc = indexOf(src, '%');
    if (pc + 1 == src.length)
        return 0;
    // Leading :: requires some special handling.
    if (src[0] == ':' && src[1] != ':')
        return 0;
    size_t j;
    ptrdiff_t colonp = -1;
    if (!parseV6Groups(src[0 .. pc], src[0] == ':', dst, j, colonp) || !expandCompression(dst, j, colonp))
        return 0;
    if (isIPv4MappedAddress(dst))
    {
        dst[0 .. INADDR4SZ] = dst[12 .. 16];
        dst[INADDR4SZ .. $] = 0;
        return INADDR4SZ;
    }
    return INADDR16SZ;
}

/// Whether a 16-byte address is IPv4-mapped: ten zero bytes, then two `0xff` bytes.
bool isIPv4MappedAddress(scope const(ubyte)[] addr) pure nothrow @nogc
{
    if (addr.length < INADDR16SZ)
        return false;
    foreach (b; addr[0 .. 10])
        if (b != 0)
            return false;
    return addr[10] == 0xff && addr[11] == 0xff;
}

/// Java's `InetAddress.checkNumericZone`: the decimal value after the first `%`, or -1 when there is no `%`, the rest
/// is not all ASCII digits, or the value overflows an `int`.
int checkNumericZone(scope const(char)[] s) pure nothrow @nogc
{
    const percent = indexOf(s, '%');
    if (percent == s.length)
        return -1;
    enum multmax = int.max / 10; // for int overflow detection
    int zone;
    foreach (c; s[percent + 1 .. $])
    {
        const digit = parseAsciiDigit(c, DECIMAL);
        if (digit < 0 || zone > multmax)
            return -1;
        zone = zone * 10 + digit;
        if (zone < 0)
            return -1;
    }
    return zone;
}

/// Java's `parseAsciiDigit`: the value of an ASCII digit in radix 8, 10 or 16, or -1.
int parseAsciiDigit(char c, int radix) pure nothrow @nogc
{
    if (radix == HEXADECIMAL)
    {
        const lower = c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c;
        if (lower >= 'a' && lower <= 'f')
            return lower - 'a' + 10;
        radix = DECIMAL;
    }
    const val = c - '0';
    return val < 0 || val >= radix ? -1 : val;
}

/// The index of the first `wanted`, or `text.length`.
size_t indexOf(scope const(char)[] text, char wanted) pure nothrow @nogc
{
    foreach (i, c; text)
        if (c == wanted)
            return i;
    return text.length;
}

private enum OCTAL = 8;
private enum DECIMAL = 10;
private enum HEXADECIMAL = 16;
private enum long CANT_PARSE_IN_RADIX = -1;
private enum long TERMINAL_PARSE_ERROR = -2;

// The group loop of Java's textToNumericFormatV6 over the text before any '%': fills dst[0 .. j] and records the
// byte index of a "::" in colonp.
private bool parseV6Groups(scope const(char)[] src, size_t i, ref ubyte[INADDR16SZ] dst, ref size_t j,
        ref ptrdiff_t colonp) pure nothrow @nogc
{
    size_t curtok = i;
    bool sawXdigit;
    int val;
    while (i < src.length)
    {
        const ch = src[i++];
        const chval = parseAsciiDigit(ch, HEXADECIMAL);
        if (chval != -1)
        {
            val = val << 4 | chval;
            if (val > 0xffff)
                return false;
            sawXdigit = true;
        }
        else if (ch == ':')
        {
            curtok = i;
            if (!sawXdigit)
            {
                if (colonp != -1)
                    return false;
                colonp = j;
            }
            else if (i == src.length || !appendGroup(dst, j, val))
                return false;
            sawXdigit = false;
            val = 0;
        }
        else if (ch == '.' && j + INADDR4SZ <= INADDR16SZ)
            return appendIPv4(src[curtok .. $], dst, j);
        else
            return false;
    }
    return !sawXdigit || appendGroup(dst, j, val);
}

private bool appendGroup(ref ubyte[INADDR16SZ] dst, ref size_t j, int val) pure nothrow @nogc
{
    if (j + INT16SZ > INADDR16SZ)
        return false;
    dst[j++] = cast(ubyte)(val >> 8);
    dst[j++] = cast(ubyte) val;
    return true;
}

// An embedded IPv4 address ends the text: it must have 3 dots, i.e. A.B.C.D.
private bool appendIPv4(scope const(char)[] ia4, ref ubyte[INADDR16SZ] dst, ref size_t j) pure nothrow @nogc
{
    int dotCount;
    foreach (c; ia4)
        dotCount += c == '.';
    ubyte[INADDR4SZ] v4addr;
    if (dotCount != 3 || !textToNumericFormatV4(ia4, v4addr))
        return false;
    dst[j .. j + INADDR4SZ] = v4addr[];
    j += INADDR4SZ;
    return true;
}

// Moves the groups after a "::" to the end of dst; true when the address then has all 16 bytes.
private bool expandCompression(ref ubyte[INADDR16SZ] dst, ref size_t j, ptrdiff_t colonp) pure nothrow @nogc
{
    if (colonp != -1)
    {
        const n = j - colonp;
        if (j == INADDR16SZ)
            return false;
        foreach (k; 1 .. n + 1)
        {
            dst[INADDR16SZ - k] = dst[colonp + n - k];
            dst[colonp + n - k] = 0;
        }
        j = INADDR16SZ;
    }
    return j == INADDR16SZ;
}

// Java's parseV4FieldBsd over a CharBuffer; `pos` is the buffer position.
private long parseV4FieldBsd(int radix, scope const(char)[] src, ref size_t pos, int fieldNumber) pure nothrow @nogc
{
    const initialPos = pos;
    long val;
    int digitsCount;
    if (!checkPrefix(src, pos, radix))
        val = CANT_PARSE_IN_RADIX;
    bool dotSeen;
    while (pos < src.length && val != CANT_PARSE_IN_RADIX && !dotSeen)
    {
        const c = src[pos++];
        if (c == '.')
        {
            dotSeen = true;
            // Too many fields, a dot with no digits, or an octet that is too big.
            if (fieldNumber == 3 || digitsCount == 0 || val > 255)
                return TERMINAL_PARSE_ERROR;
        }
        else
        {
            const dv = parseAsciiDigit(c, radix);
            if (dv < 0)
                return TERMINAL_PARSE_ERROR;
            digitsCount++;
            // Wraps like Java's long arithmetic.
            val = cast(long)(cast(ulong) val * radix + dv);
        }
    }
    if (val == CANT_PARSE_IN_RADIX)
        pos = initialPos;
    else if (!dotSeen)
    {
        // The last field of A, A.B and A.B.C fills the remaining bytes.
        const maxValue = (1L << ((4 - fieldNumber) * 8)) - 1;
        if (val > maxValue)
            return TERMINAL_PARSE_ERROR;
    }
    return val;
}

// Moves `position` past a radix prefix it accepts; the caller resets it otherwise.
private bool checkPrefix(scope const(char)[] input, ref size_t position, int radix) pure nothrow @nogc
{
    const remaining = position < input.length ? input.length - position : 0;
    switch (radix)
    {
    case OCTAL:
        // .0<EOS> is not treated as octal field, and '.0.' fields parse in decimal radix.
        if (remaining < 2 || input[position] != '0' || input[position + 1] == '.')
            return false;
        position += 1;
        return true;
    case HEXADECIMAL:
        if (remaining < 2 || input[position] != '0' || (input[position + 1] | 0x20) != 'x')
            return false;
        position += 2;
        return true;
    default:
        return remaining > 0;
    }
}
