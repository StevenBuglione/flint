// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for the existing Java output stream. */
module flint.java.io.output_stream_contract_test;

import flint.java.io : OutputStream;

@safe:

private final class RecordingSink : OutputStream
{
    ubyte[] bytes;

    override void write(int value)
    {
        bytes ~= cast(ubyte) value;
    }
}

@("OutputStream leaves resource-free sinks writable after default flush and close")
unittest
{
    static assert(__traits(isAbstractClass, OutputStream));

    auto sink = new RecordingSink;
    OutputStream stream = sink;
    stream.write(0x1FF);
    stream.flush();
    stream.write(0x180);
    stream.close();
    stream.write(-2);

    assert(sink.bytes == [cast(ubyte) 0xFF, cast(ubyte) 0x80, cast(ubyte) 0xFE]);
}
