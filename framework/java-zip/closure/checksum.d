// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.util.zip.checksum : Checksum;

@safe:

private final class ByteSum : Checksum
{
    private uint sum;

    override void update(int value) nothrow @nogc
    {
        sum += cast(ubyte) value;
    }

    override void update(scope const(byte)[] data) nothrow @nogc
    {
        foreach (value; data)
            sum += cast(ubyte) value;
    }

    override long getValue() nothrow @nogc
    {
        return sum;
    }

    override void reset() nothrow @nogc
    {
        sum = 0;
    }
}

int main(string[] args)
{
    Checksum checksum = new ByteSum();
    foreach (ubyte value; cast(const(ubyte)[]) args[0])
        checksum.update(value);
    return cast(int) checksum.getValue() & 127;
}
