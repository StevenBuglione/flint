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

@("StringWriter appends UTF-16 ranges and character arrays through Writer's adapters")
unittest
{
    auto output = new StringWriter;
    Writer writer = output;

    writer.write("a😀b", 1, 2); // the whole supplementary character
    assert(output.toString() == "😀");

    writer.write("a😀b", 2, 1); // the low surrogate alone
    assert(output.toString() == "😀\uFFFD");

    writer.write([cast(wchar) 'x', cast(wchar) 0xD83D, cast(wchar) 0xDE00]);
    assert(output.toString() == "😀\uFFFDx😀");

    writer.write([cast(wchar) 'a', cast(wchar) 0xDE00], 0, 2); // a and a lone low surrogate
    assert(output.toString() == "😀\uFFFDx😀a\uFFFD");
}

@("StringWriter.append(char) writes one unit and keeps its own type")
unittest
{
    auto output = new StringWriter;
    assert(output.append(cast(wchar) 'a') is output);
    assert(output.toString() == "a");

    Writer writer = output;
    assert(writer.append(cast(wchar) 0xD83D) is writer); // a lone high surrogate
    assert(writer.append(cast(wchar) 'b') is writer);
    assert(output.toString() == "a\uFFFDb");
}
