// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for the existing Java print writer. */
module flint.java.io.print_writer_contract_test;

import flint.java.io : ByteArrayOutputStream, PrintWriter, StringWriter, Writer;

@safe:

private final class NamedValue
{
    int calls;

    override string toString()
    {
        ++calls;
        return "named Ω";
    }
}

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

@("PrintWriter writes non-null text and returns itself from append")
unittest
{
    auto output = new StringWriter;
    auto printer = new PrintWriter(output);

    printer.write("é");
    printer.print("Ω".dup);
    printer.print(cast(wchar) 'λ');
    printer.print("");
    assert(printer.append("😀") is printer);
    assert(output.toString() == "éΩλ😀");
}

@("PrintWriter formats booleans and numeric boundaries with Java spelling")
unittest
{
    auto output = new StringWriter;
    auto printer = new PrintWriter(output);

    printer.print(true);
    printer.print("|");
    printer.print(false);
    printer.print("|");
    printer.print(int.min);
    printer.print("|");
    printer.print(int.max);
    printer.print("|");
    printer.print(long.min);
    printer.print("|");
    printer.print(long.max);
    printer.print("|");

    foreach (value; [
        float.min_normal * float.epsilon, -0.0f, float.nan, float.infinity, -float.infinity, float.max
    ])
    {
        printer.print(value);
        printer.print("|");
    }
    foreach (value; [
        double.min_normal * double.epsilon, -0.0, double.nan, double.infinity, -double.infinity,
        double.max
    ])
    {
        printer.print(value);
        printer.print("|");
    }

    assert(output.toString() == "true|false|-2147483648|2147483647|-9223372036854775808|9223372036854775807|"
            ~ "1.4E-45|-0.0|NaN|Infinity|-Infinity|3.4028235E38|"
            ~ "4.9E-324|-0.0|NaN|Infinity|-Infinity|1.7976931348623157E308|");
}

@("PrintWriter formats Object references through their virtual string representation")
unittest
{
    auto output = new StringWriter;
    auto printer = new PrintWriter(output);
    auto named = new NamedValue;
    Object value = named;
    Object missing;

    printer.print(value);
    printer.print("|");
    printer.print(missing);

    assert(output.toString() == "named Ω|null");
    assert(named.calls == 1);
}
