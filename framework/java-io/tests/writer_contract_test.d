// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for the existing Java character sink. */
module flint.java.io.writer_contract_test;

import flint.java.io : Writer;

@safe:

private final class TextSink : Writer
{
    string text;

    override void write(scope const(char)[] value)
    {
        text ~= value;
    }

    override void flush()
    {
    }

    override void close()
    {
    }
}

@("Writer append forwards text and returns the same writer")
unittest
{
    auto sink = new TextSink;
    Writer writer = sink;

    assert(writer.append("é😀") is writer);
    assert(writer.append("") is writer);
    writer.write("!");
    assert(sink.text == "é😀!");
}
