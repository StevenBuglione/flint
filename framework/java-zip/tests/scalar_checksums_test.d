// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module scalar_checksums_test;

import flint.java.util.zip : Adler32, Checksum, CRC32C;

@safe:

@("CRC32C follows pinned Java scalar checksum vectors")
unittest
{
    checkScalarVectors(new CRC32C(), 0, 0xe3069283L, 0xff000000L, 0x9c44184bL);
}

@("Adler32 follows pinned Java scalar checksum vectors")
unittest
{
    checkScalarVectors(new Adler32(), 1, 0x091e01deL, 0x01000100L, 0xadf67f81L);
}

private void checkScalarVectors(Checksum checksum, long initial, long known, long signed, long allBytes)
{
    assert(checksum.getValue() == initial);
    foreach (ubyte value; cast(const(ubyte)[]) "123456789")
        checksum.update(value);
    assert(checksum.getValue() == known);
    checksum.reset();
    assert(checksum.getValue() == initial);
    checksum.update(-1);
    assert(checksum.getValue() == signed);
    checksum.reset();
    foreach (value; 0 .. 256)
        checksum.update(0x5a0000 | value);
    assert(checksum.getValue() == allBytes);
    checksum.reset();
    assert(checksum.getValue() == initial);
}
