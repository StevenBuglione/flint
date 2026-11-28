// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for the existing Java print writer. */
module flint.java.io.print_writer_contract_test;

import flint.java.io : ByteArrayOutputStream, IOException, OutputStream, PrintWriter, StringWriter, Writer;

import std.exception : assertThrown;

import flint.java.lang : NullPointerException, System;

@safe:

@("PrintWriter rejects a null writer or output stream")
unittest
{
    assertThrown!NullPointerException(new PrintWriter(cast(Writer) null));
    assertThrown!NullPointerException(new PrintWriter(cast(OutputStream) null));
}

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

@("PrintWriter over an output stream buffers encoded text until flush or close")
unittest
{
    auto bytes = new ByteArrayOutputStream;
    auto printer = new PrintWriter(bytes);

    printer.print("é");
    assert(bytes.toByteArray().length == 0);
    printer.flush();
    assert(bytes.toByteArray() == cast(const(ubyte)[]) "é");

    printer.print("Ω");
    printer.close();
    assert(bytes.toByteArray() == cast(const(ubyte)[]) "éΩ");
}

@("PrintWriter over an output stream auto-flushes after println only when asked")
unittest
{
    auto quiet = new ByteArrayOutputStream;
    auto printer = new PrintWriter(quiet);
    printer.println("a");
    assert(quiet.toByteArray().length == 0);
    printer.flush();
    assert(quiet.toByteArray() == cast(const(ubyte)[])("a" ~ System.lineSeparator()));

    auto eager = new ByteArrayOutputStream;
    auto flushing = new PrintWriter(eager, true);
    flushing.println("b");
    assert(eager.toByteArray() == cast(const(ubyte)[])("b" ~ System.lineSeparator()));
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

private final class CountingWriter : Writer
{
    string data;
    size_t flushes;
    size_t closes;

    override void write(scope const(char)[] text)
    {
        data ~= text;
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

private final class FailingWriter : Writer
{
    bool failWrite;
    bool failFlush;
    bool failClose;
    size_t writes;
    size_t flushes;
    size_t closes;

    override void write(scope const(char)[] text)
    {
        ++writes;
        if (failWrite)
            throw new IOException("write failed");
    }

    override void flush()
    {
        ++flushes;
        if (failFlush)
            throw new IOException("flush failed");
    }

    override void close()
    {
        ++closes;
        if (failClose)
            throw new IOException("close failed");
    }
}

private final class ProbePrintWriter : PrintWriter
{
    this(Writer target, bool autoFlush = false)
    {
        super(target, autoFlush);
    }

    void markError()
    {
        setError();
    }

    void resetError()
    {
        clearError();
    }

    Writer targetOut()
    {
        return out_;
    }
}

@("PrintWriter.println terminates lines with the platform separator and auto-flushes")
unittest
{
    auto sink = new CountingWriter;
    auto printer = new PrintWriter(sink, true);

    printer.print("a");
    assert(sink.flushes == 0);
    printer.println();
    assert(sink.data == "a" ~ System.lineSeparator());
    assert(sink.flushes == 1);

    printer.println(7);
    assert(sink.data == "a" ~ System.lineSeparator() ~ "7" ~ System.lineSeparator());
    assert(sink.flushes == 2);
}

@("PrintWriter records a checked write failure and checkError flushes while open")
unittest
{
    auto sink = new FailingWriter;
    sink.failWrite = true;
    auto printer = new ProbePrintWriter(sink);

    printer.write("x");
    assert(sink.writes == 1);
    assert(printer.checkError());
    assert(sink.flushes == 1);

    printer.resetError();
    sink.failWrite = false;
    printer.write("y");
    assert(!printer.checkError());
    assert(sink.flushes == 2);
}

@("PrintWriter's protected error hooks control checkError")
unittest
{
    auto sink = new CountingWriter;
    auto printer = new ProbePrintWriter(sink);

    assert(!printer.checkError());
    printer.markError();
    assert(printer.checkError());
    printer.resetError();
    assert(!printer.checkError());
}

@("PrintWriter records a checked flush failure")
unittest
{
    auto sink = new FailingWriter;
    sink.failFlush = true;
    auto printer = new ProbePrintWriter(sink);

    printer.flush();
    assert(printer.checkError());
    printer.resetError();
    sink.failFlush = false;
    printer.flush();
    assert(!printer.checkError());
}

@("PrintWriter retains the sink after a failed close and clears it on success")
unittest
{
    auto sink = new FailingWriter;
    sink.failClose = true;
    auto printer = new ProbePrintWriter(sink);

    printer.close();
    assert(sink.closes == 1);
    assert(printer.targetOut() is sink);
    assert(printer.checkError());

    printer.resetError();
    sink.failClose = false;
    printer.close();
    assert(sink.closes == 2);
    assert(printer.targetOut() is null);

    const writes = sink.writes;
    printer.write("ignored");
    assert(sink.writes == writes);
    assert(printer.checkError());
    printer.close();
    assert(sink.closes == 2);
}

@("PrintWriter's checkError reports a nested PrintWriter's error")
unittest
{
    auto sink = new FailingWriter;
    sink.failWrite = true;
    auto inner = new PrintWriter(sink);
    inner.write("x");

    auto outer = new PrintWriter(inner);
    assert(outer.checkError());
}
