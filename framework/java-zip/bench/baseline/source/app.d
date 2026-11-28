// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import core.stdc.config : c_ulong;
import core.stdc.stdio : printf;

@safe:

private extern (C) c_ulong crc32_z(c_ulong crc, const(ubyte)* data, size_t length) @system nothrow @nogc;
private extern (C) c_ulong adler32_z(c_ulong adler, const(ubyte)* data, size_t length) @system nothrow @nogc;

private uint crc32cByte(uint remainder, ubyte value) nothrow @nogc
{
    enum uint reflectedPolynomial = 0x82F63B78;
    remainder ^= value;
    foreach (bit; 0 .. 8)
    {
        const uint lowBit = remainder & 1;
        remainder >>= 1;
        if (lowBit != 0)
            remainder ^= reflectedPolynomial;
    }
    return remainder;
}

int main(string[] args) @system
{
    const input = args.length > 1 ? args[1] : "123456789";
    c_ulong crc;
    uint crc32c = uint.max;
    c_ulong adler = 1;
    foreach (ubyte value; cast(const(ubyte)[]) input)
    {
        const ubyte[1] data = [value];
        crc = crc32_z(crc, data.ptr, data.length);
        crc32c = crc32cByte(crc32c, value);
        adler = adler32_z(adler, data.ptr, data.length);
    }
    printf("%08x %08x %08x\n", cast(uint) crc, ~crc32c, cast(uint) adler);
    return 0;
}
