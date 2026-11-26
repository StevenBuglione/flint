// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for the existing Java print writer. */
module flint.java.io.print_writer_contract_test;

import flint.java.io : ByteArrayOutputStream, PrintWriter, StringWriter, Writer;

@safe:

@("PrintWriter writes text through either supported sink")
unittest
{
    auto text = new StringWriter;
    Writer characterWriter = new PrintWriter(text);
    characterWriter.write("é😀");
    characterWriter.flush();
    characterWriter.close();
    assert(text.toString() == "é😀");

    auto bytes = new ByteArrayOutputStream;
    Writer byteWriter = new PrintWriter(bytes);
    byteWriter.write("é😀");
    byteWriter.flush();
    byteWriter.close();
    assert(bytes.toByteArray() == cast(const(ubyte)[]) "é😀");
}
