// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module scalar_checksums_test;

import flint.java.util.zip : Adler32, CRC32, Checksum, CRC32C;

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

@("Byte-array updates match the scalar path, including split and empty slices")
unittest
{
    auto crc32 = new CRC32();
    auto crc32c = new CRC32C();
    auto adler32 = new Adler32();
    const input = cast(const(byte)[]) "flint checksum array updates";

    foreach (checksum; [cast(Checksum) crc32, cast(Checksum) crc32c, cast(Checksum) adler32])
    {
        const initial = checksum.getValue();

        checksum.reset();
        checksum.update(input);
        const whole = checksum.getValue();

        checksum.reset();
        foreach (value; input)
            checksum.update(value);
        assert(checksum.getValue() == whole);

        foreach (split; 0 .. input.length + 1)
        {
            checksum.reset();
            checksum.update(input[0 .. split]);
            checksum.update(input[split .. $]);
            assert(checksum.getValue() == whole);
        }

        checksum.reset();
        checksum.update(input[0 .. 0]);
        checksum.update(null);
        assert(checksum.getValue() == initial);

        checksum.reset();
        checksum.update(input);
        checksum.update(null);
        checksum.update(input[0 .. 0]);
        assert(checksum.getValue() == whole);
    }
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
