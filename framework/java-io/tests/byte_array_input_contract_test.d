// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for the existing Java byte-array input stream. */
module flint.java.io.byte_array_input_contract_test;

import flint.java.io : ByteArrayInputStream, InputStream;

@safe:

@("ByteArrayInputStream reads the shared backing bytes as unsigned octets")
unittest
{
    ubyte[] bytes = [0x7F, 0x80, 0x00];
    auto input = new ByteArrayInputStream(bytes);
    InputStream stream = input;

    assert(input.available() == 3);
    assert(stream.read() == 0x7F);
    assert(input.available() == 2);

    bytes[2] = 0xFF;
    assert(stream.read() == 0x80);
    assert(input.available() == 1);
    stream.close();
    assert(stream.read() == 0xFF);
    assert(input.available() == 0);
    assert(stream.read() == -1);
    assert(stream.read() == -1);
}

@("ByteArrayInputStream treats a null slice as an empty buffer under R26")
unittest
{
    const(ubyte)[] absent;
    auto input = new ByteArrayInputStream(absent);
    assert(input.available() == 0);
    assert(input.read() == -1);

    ubyte[] source = [0];
    auto empty = new ByteArrayInputStream(source[0 .. 0]);
    assert(empty.available() == 0);
    assert(empty.read() == -1);
}
