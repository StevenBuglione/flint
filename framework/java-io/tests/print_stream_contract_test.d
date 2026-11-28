// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for Java's print stream. */
module flint.java.io.print_stream_contract_test;

import flint.java.io : ByteArrayOutputStream, IOException, OutputStream, OutputStreamWriter, PrintStream, PrintWriter;
import flint.java.lang : IndexOutOfBoundsException, NullPointerException, System;
import flint.java.nio.charset : Charset, IllegalCharsetNameException, StandardCharsets, UnsupportedCharsetException;

import std.exception : assertThrown;

@safe:

private final class RecordingOutput : OutputStream
{
    ubyte[] data;
    size_t flushes;
    size_t closes;
    bool failWrite;
    bool failFlush;
    bool failClose;

    override void write(int b)
    {
        if (failWrite)
            throw new IOException("write failed");
        data ~= cast(ubyte) b;
    }

    override void write(scope const(ubyte)[] b, int off, int len)
    {
        if (failWrite)
            throw new IOException("write failed");
        data ~= b[off .. off + len];
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

private final class ProbePrintStream : PrintStream
{
    this(OutputStream target, bool autoFlush = false)
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
}

@("PrintStream rejects a null output stream in every stream constructor")
unittest
{
    assertThrown!NullPointerException(new PrintStream(cast(OutputStream) null));
    assertThrown!NullPointerException(new PrintStream(cast(OutputStream) null, true));
    assertThrown!NullPointerException(new PrintStream(cast(OutputStream) null, true, StandardCharsets.UTF_8));
    assertThrown!NullPointerException(new PrintStream(cast(OutputStream) null, true, "UTF-8"));
    assertThrown!NullPointerException(new PrintStream(new ByteArrayOutputStream, true, Charset.init));
}

@("PrintStream resolves a charset name as OutputStreamWriter does")
unittest
{
    assertThrown!UnsupportedCharsetException(new PrintStream(new ByteArrayOutputStream, true, "NO-SUCH-CHARSET"));
    assertThrown!IllegalCharsetNameException(new PrintStream(new ByteArrayOutputStream, true, ""));
}

@("PrintStream prints text, primitives and raw bytes")
unittest
{
    auto bytes = new ByteArrayOutputStream;
    auto stream = new PrintStream(bytes);

    stream.print("é😀");
    stream.print(cast(wchar) '|');
    stream.print(42);
    stream.println();
    stream.writeBytes([cast(ubyte) 0x00, cast(ubyte) 0xFF]);
    stream.close();

    ubyte[] expected = (cast(const(ubyte)[]) "é😀|42").dup;
    expected ~= (cast(const(ubyte)[]) System.lineSeparator()).dup;
    expected ~= [cast(ubyte) 0x00, cast(ubyte) 0xFF];
    assert(bytes.toByteArray() == expected);
}

@("PrintStream formats values with Java spelling and treats a null array as empty (R26)")
unittest
{
    auto output = new ByteArrayOutputStream;
    auto stream = new PrintStream(output);

    stream.print(true);
    stream.print(cast(wchar) '|');
    stream.print(int.min);
    stream.print(cast(wchar) '|');
    stream.print(long.max);
    stream.print(cast(wchar) '|');
    stream.print([cast(wchar) 'A', cast(wchar) 0xD800]);
    stream.print(cast(wchar) '|');
    stream.print(cast(wchar[]) null);
    stream.println();

    ubyte[] expected = (cast(const(ubyte)[]) "true|-2147483648|9223372036854775807|A\uFFFD|").dup;
    expected ~= (cast(const(ubyte)[]) System.lineSeparator()).dup;
    assert(output.toByteArray() == expected);
}

@("PrintStream writes a UTF-16 character array and the platform line separator")
unittest
{
    auto output = new ByteArrayOutputStream;
    auto stream = new PrintStream(output);

    stream.println([cast(wchar) 'o', cast(wchar) 'k']);
    stream.println();

    ubyte[] expected = (cast(const(ubyte)[]) "ok").dup;
    expected ~= (cast(const(ubyte)[]) System.lineSeparator()).dup;
    expected ~= (cast(const(ubyte)[]) System.lineSeparator()).dup;
    assert(output.toByteArray() == expected);
}

@("PrintStream auto-flushes on a byte array write, a newline byte and println only")
unittest
{
    auto quiet = new RecordingOutput;
    auto stream = new PrintStream(quiet);
    stream.print("a");
    assert(quiet.flushes == 0);
    stream.println();
    assert(quiet.flushes == 0);
    stream.flush();
    assert(quiet.flushes == 1);

    auto eager = new RecordingOutput;
    auto flushing = new PrintStream(eager, true);
    flushing.print("a");
    assert(eager.flushes == 1); // the encoded text reaches write(byte[]) and flushes
    flushing.write(cast(ubyte) 'b');
    assert(eager.flushes == 1);
    flushing.write(cast(ubyte) '\n');
    assert(eager.flushes == 2);
    flushing.writeBytes([cast(ubyte) 'c']);
    assert(eager.flushes == 3);
    flushing.println();
    assert(eager.flushes == 5); // the buffered separator's byte-array write, then the line flush
    assert(eager.data == cast(const(ubyte)[])("ab\nc" ~ System.lineSeparator()));
}

@("PrintStream checks a byte range before handing it to the sink")
unittest
{
    auto stream = new PrintStream(new ByteArrayOutputStream);
    assertThrown!IndexOutOfBoundsException(stream.write([cast(ubyte) 1], 1, 1));
    assertThrown!IndexOutOfBoundsException(stream.write([cast(ubyte) 1], -1, 1));
    assertThrown!IndexOutOfBoundsException(stream.write([cast(ubyte) 1], 0, 2));
}

@("PrintStream records a checked write, flush or close failure")
unittest
{
    auto sink = new RecordingOutput;
    sink.failWrite = true;
    auto stream = new ProbePrintStream(sink);

    stream.write(cast(ubyte) 'x');
    assert(stream.checkError());
    stream.resetError();
    sink.failWrite = false;
    stream.write(cast(ubyte) 'y');
    assert(!stream.checkError());

    sink.failFlush = true;
    stream.flush();
    assert(stream.checkError());
    stream.resetError();
    sink.failFlush = false;

    sink.failClose = true;
    stream.close();
    assert(stream.checkError());
    assert(sink.closes == 1);
}

@("PrintStream's protected error hooks control checkError")
unittest
{
    auto stream = new ProbePrintStream(new RecordingOutput);
    assert(!stream.checkError());
    stream.markError();
    assert(stream.checkError());
    stream.resetError();
    assert(!stream.checkError());
}

@("PrintStream after close records writes and is idempotent on close")
unittest
{
    auto sink = new RecordingOutput;
    auto stream = new PrintStream(sink);
    stream.println("first");
    stream.close();
    assert(sink.closes == 1);

    stream.writeBytes([cast(ubyte) 0x41]);
    stream.write(cast(ubyte) 'B');
    stream.flush();
    assert(stream.checkError());
    stream.close();
    assert(sink.closes == 1);
}

@("PrintStream's checkError reports a wrapped print stream's error")
unittest
{
    auto sink = new RecordingOutput;
    auto inner = new PrintStream(sink);
    auto outer = new PrintStream(inner);

    sink.failWrite = true;
    outer.println("x");
    assert(outer.checkError());
}

@("PrintStream inherits a wrapped print stream's charset")
unittest
{
    auto bytes = new ByteArrayOutputStream;
    auto inner = new PrintStream(bytes, true, StandardCharsets.ISO_8859_1);
    assert(inner.charset() == StandardCharsets.ISO_8859_1);

    auto outer = new PrintStream(inner);
    assert(outer.charset() == StandardCharsets.ISO_8859_1);
    outer.print("é");
    assert(bytes.toByteArray() == cast(const(ubyte)[])[cast(ubyte) 0xE9]);
}

@("PrintStream and PrintWriter inherit the encoding of a wrapped print stream")
unittest
{
    auto bytes = new ByteArrayOutputStream;
    auto stream = new PrintStream(bytes, true, StandardCharsets.ISO_8859_1);

    auto writer = new OutputStreamWriter(stream);
    assert(Charset.forName(writer.getEncoding()) == StandardCharsets.ISO_8859_1);
    writer.write("é");
    writer.flush();
    assert(bytes.toByteArray() == cast(const(ubyte)[])[cast(ubyte) 0xE9]);

    auto printer = new PrintWriter(stream);
    printer.print("é");
    printer.flush();
    assert(bytes.toByteArray() == cast(const(ubyte)[])[cast(ubyte) 0xE9, cast(ubyte) 0xE9]);
}

@("PrintWriter's checkError reports the error of a wrapped print stream")
unittest
{
    auto sink = new RecordingOutput;
    auto stream = new PrintStream(sink);
    auto printer = new PrintWriter(stream);

    sink.failWrite = true;
    printer.println("x");
    assert(printer.checkError());
}
