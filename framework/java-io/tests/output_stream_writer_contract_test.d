// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for writing UTF-8 text to a Java byte stream. */
module flint.java.io.output_stream_writer_contract_test;

import flint.java.io : OutputStream, OutputStreamWriter, Writer;

@safe:

private final class RecordingOutput : OutputStream
{
    ubyte[] bytes;
    int flushes;
    int closes;

    override void write(int value)
    {
        bytes ~= cast(ubyte) value;
    }

    override void write(scope const(ubyte)[] data)
    {
        bytes ~= data;
    }

    override void flush()
    {
        ++flushes;
    }

    override void close()
    {
        ++closes;
    }
}

@("OutputStreamWriter writes UTF-8 for an OutputStream and forwards lifecycle calls")
unittest
{
    auto output = new RecordingOutput;
    Writer writer = new OutputStreamWriter(output);

    writer.write("é😀");
    writer.flush();
    assert(output.bytes == cast(const(ubyte)[]) "é😀");
    assert(output.flushes == 1);

    writer.write("!");
    writer.close();
    assert(output.bytes == cast(const(ubyte)[]) "é😀!");
    assert(output.closes == 1);
}
