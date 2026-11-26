// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for the existing Java string writer. */
module flint.java.io.string_writer_contract_test;

import flint.java.io : StringWriter, Writer;

@safe:

@("StringWriter starts empty and returns stable text snapshots")
unittest
{
    auto output = new StringWriter;
    assert(output.toString().length == 0);

    Writer writer = output;
    writer.write("é");
    const snapshot = output.toString();
    writer.write("");
    writer.flush();
    writer.close();
    writer.write(" 😀");

    assert(snapshot == "é");
    assert(output.toString() == "é 😀");
}
