// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.util.zip.ffi.zlib;

import core.stdc.config : c_ulong;

@safe:

version (FlintNativeZlib)
{
    private extern (C) c_ulong crc32_z(c_ulong crc, const(ubyte)* data, size_t length) @system nothrow @nogc;
}
else
{
    static assert(0, "java-zip requires the pinned Flint zlib native recipe");
}

// SAFETY: The scoped slice has at least length live bytes. zlib reads them synchronously
// and retains no pointer. A zero-length slice bypasses zlib's null-pointer reset.
package(flint.java.util.zip) uint updateCrc32(uint crc, scope const(ubyte)[] data) @trusted nothrow @nogc
{
    if (data.length == 0)
        return crc;
    return cast(uint) crc32_z(crc, data.ptr, data.length);
}

@("an empty input leaves the CRC-32 accumulator intact")
unittest
{
    const uint initial = 0xCBF43926;
    assert(updateCrc32(initial, null) == initial);
}
