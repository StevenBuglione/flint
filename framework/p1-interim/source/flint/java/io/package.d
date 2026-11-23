/++
Interim stand-in for framework-core's `flint.java.io`: `IOException`, and the `OutputStream`, `InputStream`
and `PrintWriter` shapes the servlet API exposes. Deleted when `flint:java` has them.
+/
module flint.java.io;

@safe:

/// `java.io.IOException`.
class IOException : Exception
{
    ///
    // dfmt off
    this(string message = null, Throwable cause = null, string file = __FILE__, size_t line =
            __LINE__) pure nothrow @nogc
     // dfmt on
    {
        super(message, file, line, cause);
    }

    /// Java's `getMessage()`.
    string getMessage() const pure nothrow @nogc
    {
        return msg;
    }
}

/// `java.io.OutputStream`.
abstract class OutputStream
{
    /// Writes one byte.
    abstract void write(int b);

    /// Writes `b`.
    void write(scope const(ubyte)[] b)
    {
        foreach (value; b)
            write(value);
    }

    /// Flushes buffered bytes.
    void flush()
    {
    }

    /// Closes the stream.
    void close()
    {
    }
}

/// `java.io.InputStream`.
abstract class InputStream
{
    /// The next byte, or `-1` at the end.
    abstract int read();

    /// Reads into `b`; the count, or `-1` at the end.
    int read(scope ubyte[] b)
    {
        int count;
        foreach (ref slot; b)
        {
            const value = read();
            if (value < 0)
                return count == 0 ? -1 : count;
            slot = cast(ubyte) value;
            count++;
        }
        return count;
    }

    /// Every remaining byte.
    ubyte[] readAllBytes()
    {
        ubyte[] result;
        for (int value = read(); value >= 0; value = read())
            result ~= cast(ubyte) value;
        return result;
    }

    /// Closes the stream.
    void close()
    {
    }
}

/// `java.io.Writer`, reduced to the methods servlet code calls.
abstract class Writer
{
    /// Writes `text`.
    abstract void write(scope const(char)[] text);

    /// Flushes.
    void flush()
    {
    }

    /// Closes.
    void close()
    {
    }
}

/// `java.io.PrintWriter` over a `Writer`.
class PrintWriter : Writer
{
    private Writer target;

    ///
    this(Writer target) pure nothrow @nogc
    {
        this.target = target;
    }

    override void write(scope const(char)[] text)
    {
        target.write(text);
    }

    /// Java's `print(String)`.
    void print(scope const(char)[] text)
    {
        write(text);
    }

    /// Java's `println(String)`.
    void println(scope const(char)[] text = null)
    {
        write(text);
        write("\n");
    }

    /// Java's `append(CharSequence)`.
    PrintWriter append(scope const(char)[] text)
    {
        write(text);
        return this;
    }

    override void flush()
    {
        target.flush();
    }

    override void close()
    {
        target.close();
    }
}
