// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module crc32_test;

import flint.java.util.zip : CRC32, Checksum;

@safe:

@("CRC32 computes the unsigned checksum through the Checksum contract")
unittest
{
    Checksum checksum = new CRC32();
    assert(checksum.getValue() == 0);
    foreach (ubyte value; cast(const(ubyte)[]) "123456789")
        checksum.update(value);
    assert(checksum.getValue() == 0xCBF43926L);
    checksum.reset();
    assert(checksum.getValue() == 0);
}

@("CRC32 updates only from the low byte of an int")
unittest
{
    Checksum checksum = new CRC32();
    checksum.update(-1);
    assert(checksum.getValue() == 0xFF000000L);
    checksum.reset();
    checksum.update(0x123);
    const truncated = checksum.getValue();
    checksum.reset();
    checksum.update(0x23);
    assert(checksum.getValue() == truncated);
}
