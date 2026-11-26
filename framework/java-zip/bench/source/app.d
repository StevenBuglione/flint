// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import core.stdc.stdio : printf;
import flint.java.util.zip : Adler32, CRC32, CRC32C, Checksum;

@safe:

int main(string[] args) @system
{
    const input = args.length > 1 ? args[1] : "123456789";
    Checksum crc = new CRC32();
    Checksum crc32c = new CRC32C();
    Checksum adler = new Adler32();
    foreach (ubyte value; cast(const(ubyte)[]) input)
    {
        crc.update(value);
        crc32c.update(value);
        adler.update(value);
    }
    printf("%08x %08x %08x\n", cast(uint) crc.getValue(), cast(uint) crc32c.getValue(), cast(uint) adler.getValue());
    return 0;
}
