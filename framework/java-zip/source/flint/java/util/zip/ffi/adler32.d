// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.util.zip.ffi.adler32;

import core.stdc.config : c_ulong;

@safe:

version (FlintNativeZlib)
{
    private extern (C) c_ulong adler32_z(c_ulong adler, const(ubyte)* data, size_t length) @system nothrow @nogc;
}
else
{
    static assert(0, "java-zip requires the pinned Flint zlib native recipe");
}

// SAFETY: zlib synchronously reads one byte from live stack storage and
// does not retain the pointer. The local address supplies exactly one byte.
package(flint.java.util.zip) uint updateAdler32(uint adler, ubyte value) @trusted nothrow @nogc
{
    return cast(uint) adler32_z(adler, &value, 1);
}
