// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for the existing Java byte-array output stream. */
module flint.java.io.byte_array_output_contract_test;

import flint.java.io : ByteArrayOutputStream, OutputStream;

@safe:

@("ByteArrayOutputStream keeps the low eight bits of each integer write")
unittest
{
    static assert(is(ByteArrayOutputStream : OutputStream));

    auto output = new ByteArrayOutputStream;
    assert(output.size() == 0 && output.toByteArray().length == 0);

    OutputStream sink = output;
    sink.write(0x1FF);
    sink.write(-2);
    assert(output.size() == 2);
    assert(output.toByteArray() == [cast(ubyte) 0xFF, cast(ubyte) 0xFE]);
}

@("ByteArrayOutputStream returns detached byte copies and can be reused after reset")
unittest
{
    auto output = new ByteArrayOutputStream;
    output.write(0xFF);
    output.write(0xFE);

    auto snapshot = output.toByteArray();
    snapshot[0] = 0;
    assert(output.toByteArray()[0] == 0xFF && output.size() == 2);

    output.reset();
    assert(output.size() == 0 && output.toByteArray().length == 0);
    output.write(0x7F);
    assert(output.toByteArray() == [cast(ubyte) 0x7F]);
    assert(snapshot == [cast(ubyte) 0, cast(ubyte) 0xFE]);
}
