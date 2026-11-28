/++
`java.io` as `flint.core.io.Resource` exposes it: the checked `IOException` family, `InputStream`, and `File`.

`IOException` is checked in Java; in D it is an `Exception` and the `throws` clauses are dropped (deviation D-8).
`OutputStream`, `Writer`, `StringWriter`, `OutputStreamWriter` and `PrintWriter` carry UTF-8 text.
`File` wraps a path and answers the questions `Resource` asks (`exists`, `isFile`, `length`, `lastModified`); it
does not open streams itself.
+/
module flint.java.io;

public import flint.java.io.closeable : Closeable;
public import flint.java.io.flushable : Flushable;

import flint.java.lang : RuntimeException, javaToString;

@safe:

/// Java's checked `IOException`.
class IOException : Exception
{
    private Throwable cause_;

    /// `message`, and optionally a `cause`. An empty message means no detail (R26).
    this(string message = null, Throwable cause = null, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message.length == 0 ? null : message, file, line);
        cause_ = cause is null ? this : cause;
    }

    /// `cause`: the detail is `cause.toString()`, or null when absent. An absent cause stays open for `initCause`,
    /// where Java pre-closes it (R8).
    this(Throwable cause, string file = __FILE__, size_t line = __LINE__)
    {
        super(cause is null ? null : javaToString(cause), file, line);
        cause_ = cause is null ? this : cause;
    }

    /// The detail message; null when there is none.
    string getMessage() const pure nothrow @nogc
    {
        return msg;
    }

    /// The cause; null when unknown or not set yet.
    inout(Throwable) getCause() inout pure nothrow @nogc
    {
        return cause_ is this ? null : cause_;
    }

    /// Sets the cause once, as Java's `Throwable.initCause`.
    final Throwable initCause(Throwable cause)
    {
        if (cause_ !is this)
            rejectCauseSet(cause);
        if (cause is this)
            rejectSelfCause();
        cause_ = cause;
        return this;
    }
}

/// Thrown when a file or resource does not exist or cannot be opened.
class FileNotFoundException : IOException
{
    /// `message` names the missing file.
    this(string message = null, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, null, file, line);
    }
}

/// Wraps an `IOException` where an API may not throw checked exceptions.
class UncheckedIOException : RuntimeException
{
    private IOException ioCause_;

    /// `message` and the wrapped `cause`. An empty message means no detail (R26).
    this(string message, IOException cause, string file = __FILE__, size_t line = __LINE__) pure
    {
        ioCause_ = requireIoCause(cause);
        super(message.length == 0 ? null : message, ioCause_, file, line);
    }

    /// The message is `cause.toString()`.
    this(IOException cause, string file = __FILE__, size_t line = __LINE__)
    {
        ioCause_ = requireIoCause(cause);
        super(cast(Throwable) ioCause_, file, line);
    }

    /// The checked cause supplied at construction.
    override inout(IOException) getCause() inout pure nothrow @nogc
    {
        return ioCause_;
    }
}

private IOException requireIoCause(IOException cause) pure
{
    if (cause is null)
        rejectNullIoArgument();
    return cause;
}

pragma(inline, false) private noreturn rejectNullIoArgument() pure
{
    import flint.java.lang : NullPointerException;

    throw new NullPointerException;
}

pragma(inline, false) private noreturn rejectCauseSet(Throwable cause)
{
    import flint.java.lang : IllegalStateException, javaToString;

    throw new IllegalStateException("Can't overwrite cause with " ~ (cause is null ? "a null" : javaToString(cause)));
}

pragma(inline, false) private noreturn rejectSelfCause()
{
    import flint.java.lang : IllegalArgumentException;

    throw new IllegalArgumentException("Self-causation not permitted");
}

private dchar nextPathCodePoint(scope const(char)[] text, size_t index, out size_t width) pure nothrow @nogc
{
    dchar c = text[index];
    width = 1;
    if (c >= 0x80)
    {
        if ((c & 0xE0) == 0xC0 && index + 1 < text.length)
        {
            c = ((c & 0x1F) << 6) | (text[index + 1] & 0x3F);
            width = 2;
        }
        else if ((c & 0xF0) == 0xE0 && index + 2 < text.length)
        {
            c = ((c & 0x0F) << 12) | ((text[index + 1] & 0x3F) << 6) | (text[index + 2] & 0x3F);
            width = 3;
        }
        else if ((c & 0xF8) == 0xF0 && index + 3 < text.length)
        {
            c = ((c & 0x07) << 18) | ((text[index + 1] & 0x3F) << 12) | (
                    (text[index + 2] & 0x3F) << 6) | (text[index + 3] & 0x3F);
            width = 4;
        }
    }
    return c;
}

private int comparePathnames(scope const(char)[] left, scope const(char)[] right) pure nothrow @nogc
{
    size_t i;
    size_t j;
    while (i < left.length && j < right.length)
    {
        size_t leftWidth;
        size_t rightWidth;
        const a = nextPathCodePoint(left, i, leftWidth);
        const b = nextPathCodePoint(right, j, rightWidth);
        if (a != b)
        {
            const aHigh = a >= 0x10000 ? cast(int)(0xD800 + ((a - 0x10000) >> 10)) : cast(int) a;
            const bHigh = b >= 0x10000 ? cast(int)(0xD800 + ((b - 0x10000) >> 10)) : cast(int) b;
            if (aHigh != bHigh)
                return aHigh < bHigh ? -1 : 1;
            if (a < 0x10000 || b < 0x10000)
                return 0;
            const aLow = cast(int)(0xDC00 + ((a - 0x10000) & 0x3FF));
            const bLow = cast(int)(0xDC00 + ((b - 0x10000) & 0x3FF));
            return aLow < bLow ? -1 : aLow > bLow ? 1 : 0;
        }
        i += leftWidth;
        j += rightWidth;
    }
    return i < left.length ? 1 : j < right.length ? -1 : 0;
}

/// Java's `InputStream`: a source of bytes.
abstract class InputStream : Closeable
{
    /// The next byte as 0..255, or -1 at the end.
    abstract int read();

    /// Read up to `buffer.length` bytes; the count read, or -1 at the end.
    int read(scope ubyte[] buffer)
    {
        const length = buffer.length > int.max ? int.max : cast(int) buffer.length;
        return read(buffer, 0, length);
    }

    /// Read into the requested region. A checked I/O failure after progress leaves a partial read.
    int read(scope ubyte[] buffer, int offset, int length)
    {
        checkReadRange(buffer.length, offset, length);
        if (length == 0)
            return 0;

        const first = read();
        if (first < 0)
            return -1;
        buffer[offset] = cast(ubyte) first;
        int count = 1;
        try
        {
            while (count < length)
            {
                const next = read();
                if (next < 0)
                    break;
                buffer[cast(size_t) offset + count] = cast(ubyte) next;
                ++count;
            }
        }
        catch (IOException)
        {
            // Java's default ranged read suppresses a checked failure after the first byte.
        }
        return count;
    }

    /// Read up to `length` bytes into a new array; stops at the end of the stream.
    /// A negative length is rejected before any read.
    ubyte[] readNBytes(int length)
    {
        import flint.java.lang : IllegalArgumentException;

        if (length < 0)
            throw new IllegalArgumentException("len < 0");
        enum chunkSize = 8192;
        ubyte[chunkSize] chunk;
        ubyte[] result;
        int remaining = length;
        while (remaining > 0)
        {
            const wanted = remaining < chunkSize ? remaining : chunkSize;
            const count = read(chunk[0 .. wanted]);
            if (count <= 0)
                break;
            result ~= chunk[0 .. count];
            remaining -= count;
        }
        return result;
    }

    /// Read until `length` bytes fill `buffer[offset .. offset + length]` or the stream ends.
    /// The count read is returned; zero means the stream was already at its end.
    int readNBytes(scope ubyte[] buffer, int offset, int length)
    {
        checkReadRange(buffer.length, offset, length);
        int total;
        while (total < length)
        {
            const count = read(buffer, offset + total, length - total);
            if (count <= 0)
                break;
            total += count;
        }
        return total;
    }

    /// Consume at most the requested bytes, returning the actual count.
    /// A ranged reader that makes no progress ends the skip.
    long skip(long count)
    {
        if (count <= 0)
            return 0;
        enum maxSkipBufferSize = 2048;
        const capacity = count < maxSkipBufferSize ? cast(int) count : maxSkipBufferSize;
        auto scratch = new ubyte[capacity];
        long skipped;
        while (skipped < count)
        {
            const remaining = count - skipped;
            const wanted = remaining < capacity ? cast(int) remaining : capacity;
            const consumed = read(scratch, 0, wanted);
            if (consumed <= 0)
                break;
            skipped += consumed;
        }
        return skipped;
    }

    /// Every remaining byte.
    ubyte[] readAllBytes()
    {
        ubyte[] result;
        ubyte[4096] chunk;
        for (;;)
        {
            const n = read(chunk[]);
            if (n < 0)
                return result;
            result ~= chunk[0 .. n];
        }
    }

    /// Copy every remaining byte to `target`, returning the count copied. Both streams stay open.
    long transferTo(OutputStream target)
    {
        import flint.java.lang : NullPointerException;

        if (target is null)
            throw new NullPointerException("out");
        enum chunkSize = 8192;
        ubyte[chunkSize] chunk;
        long transferred;
        for (;;)
        {
            const count = read(chunk[]);
            if (count < 0)
                break;
            target.write(chunk[0 .. count], 0, count);
            transferred += count;
        }
        return transferred;
    }

    /// How many bytes can be read without blocking. The default is zero.
    int available()
    {
        return 0;
    }

    /// Mark the current position. The default does nothing.
    void mark(int readLimit)
    {
    }

    /// Whether mark and reset are supported. The default is false.
    bool markSupported()
    {
        return false;
    }

    /// Return to the last mark. The default throws because marks are unsupported.
    void reset()
    {
        throw new IOException("mark/reset not supported");
    }

    /// Release the stream. The default does nothing.
    void close()
    {
    }
}

private void checkReadRange(size_t capacity, int offset, int length)
{
    import flint.java.lang : IndexOutOfBoundsException;

    if (offset < 0 || length < 0 || cast(size_t) offset > capacity || cast(size_t) length > capacity - offset)
        throw new IndexOutOfBoundsException("Read range exceeds the byte array");
}

/// Java's `FilterInputStream`: an input stream that delegates to a wrapped one.
class FilterInputStream : InputStream
{
    /// The wrapped stream. Java declares it `volatile`; a Flint stream is confined to one fiber.
    protected InputStream in_;

    /// Wrap `input`.
    protected this(InputStream input)
    {
        in_ = input;
    }

    alias read = InputStream.read;

    /// Delegate to the wrapped stream.
    override int read()
    {
        return in_.read();
    }

    /// Delegate to the wrapped stream.
    override int read(scope ubyte[] buffer)
    {
        const length = buffer.length > int.max ? int.max : cast(int) buffer.length;
        return read(buffer, 0, length);
    }

    /// Delegate to the wrapped stream.
    override int read(scope ubyte[] buffer, int offset, int length)
    {
        return in_.read(buffer, offset, length);
    }

    /// Delegate to the wrapped stream.
    override long skip(long count)
    {
        return in_.skip(count);
    }

    /// Delegate to the wrapped stream.
    override int available()
    {
        return in_.available();
    }

    /// Close the wrapped stream.
    override void close()
    {
        in_.close();
    }

    /// Mark the wrapped stream.
    override void mark(int readLimit)
    {
        in_.mark(readLimit);
    }

    /// Reset the wrapped stream.
    override void reset()
    {
        in_.reset();
    }

    /// Whether the wrapped stream supports marks.
    override bool markSupported()
    {
        return in_.markSupported();
    }
}

/// Copy `length` bytes between possibly overlapping byte arrays, as `System.arraycopy` does.
private void copyRange(scope ubyte[] destination, size_t destinationOffset, scope const(ubyte)[] source,
        size_t sourceOffset, size_t length) @safe
{
    if (destinationOffset < sourceOffset)
        foreach (index; 0 .. length)
            destination[destinationOffset + index] = source[sourceOffset + index];
    else
        foreach_reverse (index; 0 .. length)
            destination[destinationOffset + index] = source[sourceOffset + index];
}

/// Java's `BufferedInputStream`: buffered reads with mark and reset.
class BufferedInputStream : FilterInputStream
{
    private enum int defaultBufferSize = 8192;

    /// The internal buffer. Null once the stream is closed.
    protected ubyte[] buf;

    /// One past the last valid byte in the buffer.
    protected int count;

    /// The index of the next byte to read.
    protected int pos;

    /// The buffer index of the last mark, or -1.
    protected int markpos = -1;

    /// The read-ahead allowed after a mark.
    protected int marklimit;

    private int initialSize;

    /// Wrap `input` with the default buffer size.
    this(InputStream input)
    {
        this(input, defaultBufferSize);
    }

    /// Wrap `input` with a buffer of `size` bytes.
    this(InputStream input, int size)
    {
        super(input);
        if (size <= 0)
        {
            import flint.java.lang : IllegalArgumentException;

            throw new IllegalArgumentException("Buffer size <= 0");
        }
        initialSize = size;
        buf = new ubyte[size];
    }

    alias read = FilterInputStream.read;

    private void ensureOpen()
    {
        if (buf is null)
            throw new IOException("Stream closed");
    }

    private InputStream getInIfOpen()
    {
        InputStream input = in_;
        if (input is null)
            throw new IOException("Stream closed");
        return input;
    }

    private void fill()
    {
        if (buf is null)
            throw new IOException("Stream closed");
        if (markpos == -1)
            pos = 0;
        else if (pos >= buf.length)
        {
            if (markpos > 0)
            {
                const sz = pos - markpos;
                copyRange(buf, 0, buf, markpos, sz);
                pos = sz;
                markpos = 0;
            }
            else if (marklimit <= cast(int) buf.length)
            {
                markpos = -1;
                pos = 0;
            }
            else
            {
                int nsz = pos + (pos > 1 ? pos : 1);
                if (nsz < 0)
                    nsz = int.max;
                if (nsz > marklimit)
                    nsz = marklimit;
                ubyte[] grown = new ubyte[nsz];
                copyRange(grown, 0, buf, 0, pos);
                buf = grown;
            }
        }
        count = pos;
        const room = cast(int)(buf.length - pos);
        const n = getInIfOpen().read(buf, pos, room);
        if (n > 0)
            count = n + pos;
    }

    /// The next byte as 0..255, or -1 at the end.
    override int read()
    {
        ensureOpen();
        if (pos >= count)
        {
            fill();
            if (pos >= count)
                return -1;
        }
        return buf[pos++] & 0xFF;
    }

    private int read1(scope ubyte[] b, int off, int len)
    {
        ensureOpen();
        int avail = count - pos;
        if (avail <= 0)
        {
            const size = cast(int) buf.length > initialSize ? cast(int) buf.length : initialSize;
            if (len >= size && markpos == -1)
                return getInIfOpen().read(b, off, len);
            fill();
            avail = count - pos;
            if (avail <= 0)
                return -1;
        }
        const cnt = avail < len ? avail : len;
        copyRange(b, off, buf, pos, cnt);
        pos += cnt;
        return cnt;
    }

    /// Read into the requested region, refilling the buffer as needed.
    override int read(scope ubyte[] b, int off, int len)
    {
        ensureOpen();
        checkReadRange(b.length, off, len);
        if (len == 0)
            return 0;

        int n = 0;
        for (;;)
        {
            const nread = read1(b, off + n, len - n);
            if (nread <= 0)
                return n == 0 ? nread : n;
            n += nread;
            if (n >= len)
                return n;
            InputStream input = in_;
            if (input !is null && input.available() <= 0)
                return n;
        }
    }

    /// Consume at most `n` bytes.
    override long skip(long n)
    {
        ensureOpen();
        if (n <= 0)
            return 0;
        long avail = count - pos;
        if (avail <= 0)
        {
            if (markpos == -1)
                return getInIfOpen().skip(n);
            fill();
            avail = count - pos;
            if (avail <= 0)
                return 0;
        }
        const skipped = avail < n ? avail : n;
        pos += cast(int) skipped;
        return skipped;
    }

    /// The buffered bytes plus the wrapped stream's estimate.
    override int available()
    {
        const n = count - pos;
        const avail = getInIfOpen().available();
        return n > (int.max - avail) ? int.max : n + avail;
    }

    /// Remember the current position.
    override void mark(int readLimit)
    {
        marklimit = readLimit;
        markpos = pos;
    }

    /// Return to the last mark.
    override void reset()
    {
        ensureOpen();
        if (markpos < 0)
            throw new IOException("Resetting to invalid mark");
        pos = markpos;
    }

    /// Marks are supported.
    override bool markSupported()
    {
        return true;
    }

    /// Close the wrapped stream once; later operations report a closed stream.
    override void close()
    {
        ubyte[] buffer = buf;
        buf = null;
        if (buffer !is null)
        {
            InputStream input = in_;
            in_ = null;
            if (input !is null)
                input.close();
        }
    }
}

/// Java's `PushbackInputStream`: an input stream with a pushback buffer.
class PushbackInputStream : FilterInputStream
{
    /// The pushback buffer. Null once the stream is closed.
    protected ubyte[] buf;

    /// The index of the next pushed-back byte; `buf.length` when empty.
    protected int pos;

    /// Wrap `input` with a one-byte pushback buffer.
    this(InputStream input)
    {
        this(input, 1);
    }

    /// Wrap `input` with a pushback buffer of `size` bytes.
    this(InputStream input, int size)
    {
        super(input);
        if (size <= 0)
        {
            import flint.java.lang : IllegalArgumentException;

            throw new IllegalArgumentException("size <= 0");
        }
        buf = new ubyte[size];
        pos = size;
    }

    alias read = FilterInputStream.read;

    private void ensureOpen()
    {
        if (in_ is null)
            throw new IOException("Stream closed");
    }

    /// The next pushed-back byte, or the wrapped stream's next byte.
    override int read()
    {
        ensureOpen();
        if (pos < buf.length)
            return buf[pos++] & 0xFF;
        return super.read();
    }

    /// Read pushed-back bytes first, then from the wrapped stream.
    override int read(scope ubyte[] b, int off, int len)
    {
        ensureOpen();
        checkReadRange(b.length, off, len);
        if (len == 0)
            return 0;

        int avail = cast(int)(buf.length - pos);
        if (avail > 0)
        {
            if (len < avail)
                avail = len;
            copyRange(b, off, buf, pos, avail);
            pos += avail;
            off += avail;
            len -= avail;
        }
        if (len > 0)
        {
            const count = super.read(b, off, len);
            if (count == -1)
                return avail == 0 ? -1 : avail;
            return avail + count;
        }
        return avail;
    }

    /// Push one byte back.
    void unread(int b)
    {
        ensureOpen();
        if (pos == 0)
            throw new IOException("Push back buffer is full");
        buf[--pos] = cast(ubyte) b;
    }

    /// Push `len` bytes of `b` from `off` back.
    void unread(scope const(ubyte)[] b, int off, int len)
    {
        ensureOpen();
        if (len > pos)
            throw new IOException("Push back buffer is full");
        checkReadRange(b.length, off, len);
        pos -= len;
        copyRange(buf, pos, b, off, len);
    }

    /// Push every byte of `b` back.
    void unread(scope const(ubyte)[] b)
    {
        unread(b, 0, cast(int) b.length);
    }

    /// The pushed-back bytes plus the wrapped stream's estimate.
    override int available()
    {
        ensureOpen();
        const n = cast(int)(buf.length - pos);
        const avail = super.available();
        return n > (int.max - avail) ? int.max : n + avail;
    }

    /// Skip pushed-back bytes first, then the wrapped stream.
    override long skip(long n)
    {
        ensureOpen();
        if (n <= 0)
            return 0;

        long skipped = buf.length - pos;
        if (skipped > 0)
        {
            if (n < skipped)
                skipped = n;
            pos += cast(int) skipped;
            n -= skipped;
        }
        if (n > 0)
            skipped += super.skip(n);
        return skipped;
    }

    /// Marks are not supported.
    override bool markSupported()
    {
        return false;
    }

    /// Marks are not supported, so this does nothing.
    override void mark(int readLimit)
    {
    }

    /// Marks are not supported.
    override void reset()
    {
        throw new IOException("mark/reset not supported");
    }

    /// Close the wrapped stream once.
    override void close()
    {
        if (in_ !is null)
        {
            in_.close();
            in_ = null;
            buf = null;
        }
    }
}

/// Java's `OutputStream`: a sink of bytes.
abstract class OutputStream : Closeable, Flushable
{
    /// Write one byte (the low 8 bits of `b`).
    abstract void write(int b);

    /// Write every byte of `b`.
    void write(scope const(ubyte)[] b)
    {
        // D slices can exceed the length representable by Java's int indices.
        for (; b.length > int.max; b = b[int.max .. $])
            write(b[0 .. int.max], 0, int.max);
        write(b, 0, cast(int) b.length);
    }

    /// Write `len` bytes of `b` from `off`.
    void write(scope const(ubyte)[] b, int off, int len)
    {
        foreach (value; b[off .. byteWriteEnd(b.length, off, len)])
            write(cast(byte) value);
    }

    /// Flush buffered bytes. The default does nothing.
    void flush()
    {
    }

    /// Release the stream. The default does nothing.
    void close()
    {
    }
}

package(flint) size_t byteWriteEnd(size_t capacity, int offset, int count)
{
    import flint.java.lang : IndexOutOfBoundsException;

    if (offset < 0 || count < 0 || cast(size_t) offset > capacity || cast(size_t) count > capacity - offset)
        throw new IndexOutOfBoundsException;
    return cast(size_t) offset + count;
}

/// An `OutputStream` collecting bytes in memory.
class ByteArrayOutputStream : OutputStream
{
    /// Java's `buf`: the capacity buffer. A D `ubyte` slice under R26.
    protected ubyte[] buf;

    /// The number of valid bytes in `buf`.
    protected int count;

    alias write = OutputStream.write;

    /// A stream with the default 32-byte capacity.
    this()
    {
        this(32);
    }

    /// A stream with `size` bytes of initial capacity.
    this(int size)
    {
        if (size < 0)
        {
            import flint.java.lang : IllegalArgumentException;

            throw new IllegalArgumentException(negativeSizeMessage(size));
        }
        buf = new ubyte[size];
    }

    private void ensureCapacity(int minimum)
    {
        const oldCapacity = cast(int) buf.length;
        const minimumGrowth = minimum - oldCapacity;
        if (minimumGrowth <= 0)
            return;
        const growth = minimumGrowth > oldCapacity ? minimumGrowth : oldCapacity;
        ubyte[] grown = new ubyte[oldCapacity + growth];
        copyRange(grown, 0, buf, 0, buf.length);
        buf = grown;
    }

    override void write(int b)
    {
        ensureCapacity(count + 1);
        buf[count] = cast(ubyte) b;
        count += 1;
    }

    override void write(scope const(ubyte)[] b, int off, int len)
    {
        byteWriteEnd(b.length, off, len);
        ensureCapacity(count + len);
        copyRange(buf, count, b, off, len);
        count += len;
    }

    /// Write every byte of `b`.
    void writeBytes(scope const(ubyte)[] b)
    {
        write(b, 0, cast(int) b.length);
    }

    /// Write the accumulated bytes to `out` without clearing them.
    void writeTo(OutputStream target)
    {
        import flint.java.lang : NullPointerException;

        if (target is null)
            throw new NullPointerException("out");
        target.write(buf[0 .. count].dup);
    }

    /// A copy of the bytes written.
    ubyte[] toByteArray() const pure
    {
        return buf[0 .. count].dup;
    }

    /// How many bytes were written.
    int size() const pure nothrow @nogc
    {
        return count;
    }

    /// Discard the bytes written, keeping the capacity.
    void reset() pure nothrow @nogc
    {
        count = 0;
    }

    /// The bytes decoded as UTF-8 text, each malformed sequence replaced with U+FFFD.
    override string toString() const
    {
        import flint.engine.aot.text : decodeUtf8, isValidUtf8;

        const bytes = cast(const(char)[]) buf[0 .. count];
        if (isValidUtf8(bytes))
            return bytes.idup;
        char[] text;
        size_t i;
        while (i < bytes.length)
        {
            const start = i;
            const codePoint = decodeUtf8(bytes, i);
            if (codePoint == 0xFFFD && bytes[start .. i] != "\xEF\xBF\xBD")
                text ~= "\xEF\xBF\xBD";
            else
                text ~= bytes[start .. i];
        }
        return text.idup;
    }
}

private string negativeSizeMessage(int size)
{
    char[12] digits;
    size_t start = digits.length;
    auto value = -cast(long) size;
    do
    {
        digits[--start] = cast(char)('0' + value % 10);
        value /= 10;
    }
    while (value != 0);
    digits[--start] = '-';
    return ("Negative initial size: " ~ digits[start .. $]).idup;
}

/// Java's `FilterOutputStream`: an output stream that delegates to a wrapped one.
class FilterOutputStream : OutputStream
{
    /// The wrapped stream. Java names it `out`; `out` is a D keyword.
    protected OutputStream out_;

    private bool closed_;
    private Object closeLock;

    /// Wrap `output`.
    this(OutputStream output)
    {
        out_ = output;
        closeLock = new Object;
    }

    alias write = OutputStream.write;

    /// Delegate to the wrapped stream.
    override void write(int value)
    {
        out_.write(value);
    }

    /// Delegate to the wrapped stream.
    override void write(scope const(ubyte)[] b)
    {
        for (; b.length > int.max; b = b[int.max .. $])
            write(b[0 .. int.max], 0, int.max);
        write(b, 0, cast(int) b.length);
    }

    /// Check the range, then write each byte through `write(int)`, as Java does.
    override void write(scope const(ubyte)[] b, int off, int len)
    {
        foreach (value; b[off .. byteWriteEnd(b.length, off, len)])
            write(cast(int) value);
    }

    /// Flush the wrapped stream.
    override void flush()
    {
        out_.flush();
    }

    /// Flush and close the wrapped stream once.
    override void close()
    {
        if (closed_)
            return;
        synchronized (closeLock)
        {
            if (closed_)
                return;
            closed_ = true;
        }
        try
        {
            flush();
        }
        catch (Exception flushFailure)
        {
            try
                out_.close();
            catch (Exception)
            {
                // Java records this close failure as a suppressed exception on flushFailure;
                // Flint's Throwable has no suppressed-exception API.
            }
            throw flushFailure;
        }
        out_.close();
    }
}

/// Java's `BufferedOutputStream`: buffered writes to a wrapped stream.
class BufferedOutputStream : FilterOutputStream
{
    private enum int defaultInitialBufferSize = 512;
    private enum int defaultMaxBufferSize = 8192;

    /// The internal buffer.
    protected ubyte[] buf;

    /// The number of valid bytes in the buffer.
    protected int count;

    private int maxBufSize;

    /// Wrap `output` with the default buffer size.
    this(OutputStream output)
    {
        this(output, defaultMaxBufferSize, defaultMaxBufferSize);
    }

    /// Wrap `output` with a buffer of `size` bytes.
    this(OutputStream output, int size)
    {
        this(output, size, size);
    }

    private this(OutputStream output, int initialSize, int maxSize)
    {
        super(output);
        if (initialSize <= 0)
        {
            import flint.java.lang : IllegalArgumentException;

            throw new IllegalArgumentException("Buffer size <= 0");
        }
        buf = new ubyte[initialSize];
        maxBufSize = maxSize;
    }

    alias write = FilterOutputStream.write;

    private void flushBuffer()
    {
        if (count > 0)
        {
            out_.write(buf, 0, count);
            count = 0;
        }
    }

    private void growIfNeeded(int length)
    {
        int neededSize = count + length + 1;
        if (neededSize < 0)
            neededSize = int.max;
        const bufSize = cast(int) buf.length;
        if (neededSize > bufSize && bufSize < maxBufSize)
        {
            const newSize = neededSize < maxBufSize ? neededSize : maxBufSize;
            ubyte[] grown = new ubyte[newSize];
            copyRange(grown, 0, buf, 0, buf.length);
            buf = grown;
        }
    }

    /// Buffer one byte, flushing the buffer first when it is full.
    override void write(int value)
    {
        growIfNeeded(1);
        if (count >= buf.length)
            flushBuffer();
        buf[count++] = cast(ubyte) value;
    }

    /// Buffer bytes, or pass a large write straight through after flushing.
    override void write(scope const(ubyte)[] b, int off, int len)
    {
        if (len >= maxBufSize)
        {
            flushBuffer();
            out_.write(b, off, len);
            return;
        }
        growIfNeeded(len);
        if (len > cast(int)(buf.length - count))
            flushBuffer();
        byteWriteEnd(b.length, off, len);
        copyRange(buf, count, b, off, len);
        count += len;
    }

    /// Flush the buffer, then the wrapped stream.
    override void flush()
    {
        flushBuffer();
        out_.flush();
    }
}

/// Java's `DataOutput`: a portable sink of primitive Java values.
interface DataOutput
{
    /// Write one byte (the low 8 bits of `b`).
    void write(int b);

    /// Write every byte of `b`.
    void write(scope const(ubyte)[] b);

    /// Write `len` bytes of `b` from `off`.
    void write(scope const(ubyte)[] b, int off, int len);

    /// Write a boolean as one byte.
    void writeBoolean(bool v);

    /// Write a byte as one byte.
    void writeByte(int v);

    /// Write a short as two bytes, high byte first.
    void writeShort(int v);

    /// Write a char as two bytes, high byte first.
    void writeChar(int v);

    /// Write an int as four bytes, high byte first.
    void writeInt(int v);

    /// Write a long as eight bytes, high byte first.
    void writeLong(long v);

    /// Write a float as four bytes, high byte first.
    void writeFloat(float v);

    /// Write a double as eight bytes, high byte first.
    void writeDouble(double v);

    /// Write each UTF-16 code unit's low eight bits.
    void writeBytes(scope const(char)[] s);

    /// Write each UTF-16 code unit as two bytes, high byte first.
    void writeChars(scope const(char)[] s);

    /// Write `s` in modified UTF-8 with a two-byte length prefix.
    void writeUTF(scope const(char)[] s);
}

/// The canonical Java `floatToIntBits` value of `value`.
private int javaFloatBits(float value) pure nothrow @nogc
{
    if (value != value)
        return 0x7FC0_0000;
    union Bits
    {
        float f;
        uint u;
    }

    Bits bits;
    bits.f = value;
    return cast(int) bits.u;
}

/// The canonical Java `doubleToLongBits` value of `value`.
private long javaDoubleBits(double value) pure nothrow @nogc
{
    if (value != value)
        return 0x7FF8_0000_0000_0000L;
    union Bits
    {
        double d;
        ulong u;
    }

    Bits bits;
    bits.d = value;
    return cast(long) bits.u;
}

/// The next code point of `text`, advancing `index` past it.
private dchar nextCodePoint(scope const(char)[] text, ref size_t index) pure nothrow @nogc
{
    import flint.engine.aot.text : decodeUtf8;

    return decodeUtf8(text, index);
}

private void putUnsignedShort(scope ubyte[] buffer, int offset, int value) pure nothrow @nogc
{
    buffer[offset] = cast(ubyte)(value >>> 8);
    buffer[offset + 1] = cast(ubyte) value;
}

private void putInt(scope ubyte[] buffer, int offset, int value) pure nothrow @nogc
{
    buffer[offset] = cast(ubyte)(value >>> 24);
    buffer[offset + 1] = cast(ubyte)(value >>> 16);
    buffer[offset + 2] = cast(ubyte)(value >>> 8);
    buffer[offset + 3] = cast(ubyte) value;
}

private void putLong(scope ubyte[] buffer, int offset, long value) pure nothrow @nogc
{
    buffer[offset] = cast(ubyte)(value >>> 56);
    buffer[offset + 1] = cast(ubyte)(value >>> 48);
    buffer[offset + 2] = cast(ubyte)(value >>> 40);
    buffer[offset + 3] = cast(ubyte)(value >>> 32);
    buffer[offset + 4] = cast(ubyte)(value >>> 24);
    buffer[offset + 5] = cast(ubyte)(value >>> 16);
    buffer[offset + 6] = cast(ubyte)(value >>> 8);
    buffer[offset + 7] = cast(ubyte) value;
}

/// Java's `DataOutputStream`: primitive values written in Java's portable form.
class DataOutputStream : FilterOutputStream, DataOutput
{
    /// The number of bytes written so far, saturating at `int.max`.
    protected int written;

    private ubyte[] bytearr;
    private ubyte[8] writeBuffer;

    /// Wrap `output`.
    this(OutputStream output)
    {
        super(output);
    }

    alias write = FilterOutputStream.write;

    private void incCount(int value)
    {
        int temp = written + value;
        if (temp < 0)
            temp = int.max;
        written = temp;
    }

    /// Write one byte and count it.
    override void write(int value)
    {
        out_.write(value);
        incCount(1);
    }

    /// Write every byte of `b` and count them.
    override void write(scope const(ubyte)[] b)
    {
        super.write(b);
    }

    /// Write a range and count it.
    override void write(scope const(ubyte)[] b, int off, int len)
    {
        out_.write(b, off, len);
        incCount(len);
    }

    /// Flush the wrapped stream.
    override void flush()
    {
        out_.flush();
    }

    /// Write a boolean as one byte.
    final void writeBoolean(bool v)
    {
        out_.write(v ? 1 : 0);
        incCount(1);
    }

    /// Write a byte as one byte.
    final void writeByte(int v)
    {
        out_.write(v);
        incCount(1);
    }

    /// Write a short as two bytes, high byte first.
    final void writeShort(int v)
    {
        putUnsignedShort(writeBuffer, 0, v);
        out_.write(writeBuffer, 0, 2);
        incCount(2);
    }

    /// Write a char as two bytes, high byte first.
    final void writeChar(int v)
    {
        putUnsignedShort(writeBuffer, 0, v);
        out_.write(writeBuffer, 0, 2);
        incCount(2);
    }

    /// Write an int as four bytes, high byte first.
    final void writeInt(int v)
    {
        putInt(writeBuffer, 0, v);
        out_.write(writeBuffer, 0, 4);
        incCount(4);
    }

    /// Write a long as eight bytes, high byte first.
    final void writeLong(long v)
    {
        putLong(writeBuffer, 0, v);
        out_.write(writeBuffer, 0, 8);
        incCount(8);
    }

    /// Write a float as four bytes, high byte first.
    final void writeFloat(float v)
    {
        putInt(writeBuffer, 0, javaFloatBits(v));
        out_.write(writeBuffer, 0, 4);
        incCount(4);
    }

    /// Write a double as eight bytes, high byte first.
    final void writeDouble(double v)
    {
        putLong(writeBuffer, 0, javaDoubleBits(v));
        out_.write(writeBuffer, 0, 8);
        incCount(8);
    }

    /// Write each UTF-16 code unit's low eight bits.
    final void writeBytes(scope const(char)[] s)
    {
        size_t index;
        int units;
        while (index < s.length)
        {
            const c = nextCodePoint(s, index);
            if (c > 0xFFFF)
            {
                const v = c - 0x10000;
                out_.write(cast(int)(0xD800 + (v >> 10)));
                out_.write(cast(int)(0xDC00 + (v & 0x3FF)));
                units += 2;
            }
            else
            {
                out_.write(cast(int) c);
                ++units;
            }
        }
        incCount(units);
    }

    /// Write each UTF-16 code unit as two bytes, high byte first.
    final void writeChars(scope const(char)[] s)
    {
        size_t index;
        int units;
        while (index < s.length)
        {
            const c = nextCodePoint(s, index);
            if (c > 0xFFFF)
            {
                const v = c - 0x10000;
                putUnsignedShort(writeBuffer, 0, cast(int)(0xD800 + (v >> 10)));
                out_.write(writeBuffer, 0, 2);
                putUnsignedShort(writeBuffer, 0, cast(int)(0xDC00 + (v & 0x3FF)));
                out_.write(writeBuffer, 0, 2);
                units += 2;
            }
            else
            {
                putUnsignedShort(writeBuffer, 0, cast(int) c);
                out_.write(writeBuffer, 0, 2);
                ++units;
            }
        }
        incCount(units * 2);
    }

    /// Write `s` in modified UTF-8 with a two-byte length prefix.
    final void writeUTF(scope const(char)[] s)
    {
        size_t index;
        long length;
        while (index < s.length)
        {
            const c = nextCodePoint(s, index);
            if (c == 0)
                length += 2;
            else if (c < 0x80)
                length += 1;
            else if (c < 0x800)
                length += 2;
            else if (c <= 0xFFFF)
                length += 3;
            else
                length += 6;
        }
        if (length > 0xFFFF)
        {
            import flint.engine.aot.text : decimal;

            throw new UTFDataFormatException("encoded string too long: " ~ decimal(length) ~ " bytes");
        }

        const total = cast(int) length + 2;
        if (bytearr.length < total)
        {
            bytearr = new ubyte[(cast(size_t) length * 2) + 2];
        }
        putUnsignedShort(bytearr, 0, cast(int) length);
        int offset = 2;
        index = 0;
        while (index < s.length)
        {
            const c = nextCodePoint(s, index);
            if (c != 0 && c < 0x80)
            {
                bytearr[offset++] = cast(ubyte) c;
            }
            else if (c < 0x800)
            {
                bytearr[offset++] = cast(ubyte)(0xC0 | (c >> 6));
                bytearr[offset++] = cast(ubyte)(0x80 | (c & 0x3F));
            }
            else if (c <= 0xFFFF)
            {
                bytearr[offset++] = cast(ubyte)(0xE0 | (c >> 12));
                bytearr[offset++] = cast(ubyte)(0x80 | ((c >> 6) & 0x3F));
                bytearr[offset++] = cast(ubyte)(0x80 | (c & 0x3F));
            }
            else
            {
                const v = c - 0x10000;
                const high = 0xD800 + (v >> 10);
                const low = 0xDC00 + (v & 0x3FF);
                bytearr[offset++] = cast(ubyte)(0xE0 | (high >> 12));
                bytearr[offset++] = cast(ubyte)(0x80 | ((high >> 6) & 0x3F));
                bytearr[offset++] = cast(ubyte)(0x80 | (high & 0x3F));
                bytearr[offset++] = cast(ubyte)(0xE0 | (low >> 12));
                bytearr[offset++] = cast(ubyte)(0x80 | ((low >> 6) & 0x3F));
                bytearr[offset++] = cast(ubyte)(0x80 | (low & 0x3F));
            }
        }
        write(bytearr, 0, total);
    }

    /// The number of bytes written so far.
    final int size() pure nothrow @nogc
    {
        return written;
    }
}

/// Java's `DataInput`: a portable source of primitive Java values.
interface DataInput
{
    /// Read `b.length` bytes or fail at the end of the stream.
    void readFully(scope ubyte[] b);

    /// Read `len` bytes from `off` or fail at the end of the stream.
    void readFully(scope ubyte[] b, int off, int len);

    /// Skip `n` bytes, returning the count actually skipped.
    int skipBytes(int n);

    /// Read a boolean.
    bool readBoolean();

    /// Read a signed byte.
    byte readByte();

    /// Read an unsigned byte as 0..255.
    int readUnsignedByte();

    /// Read a signed short.
    short readShort();

    /// Read an unsigned short as 0..65535.
    int readUnsignedShort();

    /// Read a UTF-16 code unit.
    wchar readChar();

    /// Read an int.
    int readInt();

    /// Read a long.
    long readLong();

    /// Read a float.
    float readFloat();

    /// Read a double.
    double readDouble();

    /// Read modified UTF-8 with a two-byte length prefix.
    string readUTF();
}

private int readIntBits(scope const(ubyte)[] buffer, int offset) pure nothrow @nogc
{
    return (cast(int) buffer[offset] << 24) | (cast(int) buffer[offset + 1] << 16) | (
            cast(int) buffer[offset + 2] << 8) | cast(int) buffer[offset + 3];
}

private long readLongBits(scope const(ubyte)[] buffer, int offset) pure nothrow @nogc
{
    return (cast(long) buffer[offset] << 56) | (cast(long) buffer[offset + 1] << 48) | (
            cast(long) buffer[offset + 2] << 40) | (cast(long) buffer[offset + 3] << 32) | (
            cast(long) buffer[offset + 4] << 24) | (cast(long) buffer[offset + 5] << 16) | (
            cast(long) buffer[offset + 6] << 8) | cast(long) buffer[offset + 7];
}

private void putCodePoint(scope char[] output, ref size_t used, int codePoint) pure nothrow @nogc
{
    if (codePoint >= 0xD800 && codePoint <= 0xDFFF)
        codePoint = 0xFFFD; // an unpaired surrogate has no UTF-8 form
    if (codePoint < 0x80)
        output[used++] = cast(char) codePoint;
    else if (codePoint < 0x800)
    {
        output[used++] = cast(char)(0xC0 | (codePoint >> 6));
        output[used++] = cast(char)(0x80 | (codePoint & 0x3F));
    }
    else if (codePoint < 0x10000)
    {
        output[used++] = cast(char)(0xE0 | (codePoint >> 12));
        output[used++] = cast(char)(0x80 | ((codePoint >> 6) & 0x3F));
        output[used++] = cast(char)(0x80 | (codePoint & 0x3F));
    }
    else
    {
        output[used++] = cast(char)(0xF0 | (codePoint >> 18));
        output[used++] = cast(char)(0x80 | ((codePoint >> 12) & 0x3F));
        output[used++] = cast(char)(0x80 | ((codePoint >> 6) & 0x3F));
        output[used++] = cast(char)(0x80 | (codePoint & 0x3F));
    }
}

/// Java's `DataInputStream`: primitive values read in Java's portable form.
class DataInputStream : FilterInputStream, DataInput
{
    private ubyte[8] readBuffer;
    private PushbackInputStream readLinePushback;

    /// Wrap `input`.
    this(InputStream input)
    {
        super(input);
    }

    alias read = FilterInputStream.read;

    /// Read every byte of `b` through the wrapped stream.
    override final int read(scope ubyte[] b)
    {
        return in_.read(b);
    }

    /// Read a range through the wrapped stream.
    override final int read(scope ubyte[] b, int off, int len)
    {
        return in_.read(b, off, len);
    }

    /// Read `b.length` bytes or fail at the end of the stream.
    final void readFully(scope ubyte[] b)
    {
        readFully(b, 0, cast(int) b.length);
    }

    /// Read `len` bytes from `off` or fail at the end of the stream.
    final void readFully(scope ubyte[] b, int off, int len)
    {
        checkReadRange(b.length, off, len);
        int n = 0;
        while (n < len)
        {
            const count = in_.read(b, off + n, len - n);
            if (count < 0)
                throw new EOFException;
            n += count;
        }
    }

    /// Skip `n` bytes, returning the count actually skipped.
    final int skipBytes(int n)
    {
        int total;
        int cur;
        while (total < n && (cur = cast(int) in_.skip(n - total)) > 0)
            total += cur;
        return total;
    }

    /// Read a boolean.
    final bool readBoolean()
    {
        return readUnsignedByte() != 0;
    }

    /// Read a signed byte.
    final byte readByte()
    {
        return cast(byte) readUnsignedByte();
    }

    /// Read an unsigned byte as 0..255.
    final int readUnsignedByte()
    {
        const ch = in_.read();
        if (ch < 0)
            throw new EOFException;
        return ch;
    }

    /// Read a signed short.
    final short readShort()
    {
        readFully(readBuffer, 0, 2);
        return cast(short)((cast(int) readBuffer[0] << 8) | cast(int) readBuffer[1]);
    }

    /// Read an unsigned short as 0..65535.
    final int readUnsignedShort()
    {
        readFully(readBuffer, 0, 2);
        return (cast(int) readBuffer[0] << 8) | cast(int) readBuffer[1];
    }

    /// Read a UTF-16 code unit.
    final wchar readChar()
    {
        readFully(readBuffer, 0, 2);
        return cast(wchar)((cast(int) readBuffer[0] << 8) | cast(int) readBuffer[1]);
    }

    /// Read an int.
    final int readInt()
    {
        readFully(readBuffer, 0, 4);
        return readIntBits(readBuffer, 0);
    }

    /// Read a long.
    final long readLong()
    {
        readFully(readBuffer, 0, 8);
        return readLongBits(readBuffer, 0);
    }

    /// Read a float.
    final float readFloat()
    {
        readFully(readBuffer, 0, 4);
        union Bits
        {
            int i;
            float f;
        }

        Bits bits;
        bits.i = readIntBits(readBuffer, 0);
        return bits.f;
    }

    /// Read a double.
    final double readDouble()
    {
        readFully(readBuffer, 0, 8);
        union Bits
        {
            long l;
            double d;
        }

        Bits bits;
        bits.l = readLongBits(readBuffer, 0);
        return bits.d;
    }

    /// Read a line of text; each byte becomes one UTF-16 code unit, as Java does.
    final string readLine()
    {
        ubyte[] line;
        size_t used;
        int c;
        loop: for (;;)
        {
            c = in_.read();
            switch (c)
            {
            case -1:
            case '\n':
                break loop;
            case '\r':
                const c2 = in_.read();
                if (c2 != '\n' && c2 != -1)
                {
                    PushbackInputStream pushback = readLinePushback;
                    if (pushback is null)
                    {
                        pushback = new PushbackInputStream(in_);
                        in_ = pushback;
                        readLinePushback = pushback;
                    }
                    pushback.unread(c2);
                }
                break loop;
            default:
                if (used == line.length)
                {
                    const grownLength = line.length ? line.length * 2 : 128;
                    ubyte[] grown = new ubyte[grownLength];
                    if (line.length)
                        copyRange(grown, 0, line, 0, line.length);
                    line = grown;
                }
                line[used++] = cast(ubyte) c;
                break;
            }
        }
        if (c == -1 && used == 0)
            return null;
        return latin1String(line[0 .. used]);
    }

    private static string latin1String(scope const(ubyte)[] bytes)
    {
        size_t length;
        foreach (b; bytes)
            length += b < 0x80 ? 1 : 2;
        char[] result = new char[length];
        size_t index;
        foreach (b; bytes)
        {
            if (b < 0x80)
                result[index++] = cast(char) b;
            else
            {
                result[index++] = cast(char)(0xC0 | (b >> 6));
                result[index++] = cast(char)(0x80 | (b & 0x3F));
            }
        }
        return result.idup;
    }

    /// Read modified UTF-8 with a two-byte length prefix.
    final string readUTF()
    {
        return readUTF(this);
    }

    /// Read modified UTF-8 from `input`.
    static string readUTF(DataInput input)
    {
        const utflen = input.readUnsignedShort();
        ubyte[256] stackBytes;
        char[768] stackChars;
        ubyte[] bytes = stackBytes[];
        char[] output = stackChars[];
        if (utflen > stackBytes.length)
            bytes = new ubyte[utflen];
        if (cast(size_t) utflen * 3 > stackChars.length)
            output = new char[utflen * 3];
        input.readFully(bytes, 0, utflen);

        size_t count;
        size_t used;
        while (count < utflen)
        {
            const c = bytes[count] & 0xFF;
            if (c > 127)
                break;
            ++count;
            output[used++] = cast(char) c;
        }
        while (count < utflen)
            count = decodeUnit(bytes, count, utflen, output, used);
        return output[0 .. used].idup;
    }

    private static size_t decodeUnit(scope const(ubyte)[] bytes, size_t count, size_t utflen,
            scope char[] output, ref size_t used)
    {
        const c = bytes[count] & 0xFF;
        if (c < 0x80)
        {
            output[used++] = cast(char) c;
            return count + 1;
        }
        if ((c & 0xE0) == 0xC0)
            return decodeTwoByte(bytes, count, utflen, output, used, c);
        if ((c & 0xF0) == 0xE0)
            return decodeThreeByte(bytes, count, utflen, output, used, c);
        throw malformedAt(count);
    }

    private static size_t decodeTwoByte(scope const(ubyte)[] bytes, size_t count, size_t utflen,
            scope char[] output, ref size_t used, int c)
    {
        count += 2;
        if (count > utflen)
            throw partialCharacter();
        const char2 = bytes[count - 1];
        if ((char2 & 0xC0) != 0x80)
            throw malformedAt(count);
        putCodePoint(output, used, ((c & 0x1F) << 6) | (char2 & 0x3F));
        return count;
    }

    private static size_t decodeThreeByte(scope const(ubyte)[] bytes, size_t count, size_t utflen,
            scope char[] output, ref size_t used, int c)
    {
        count += 3;
        if (count > utflen)
            throw partialCharacter();
        const char2 = bytes[count - 2];
        const char3 = bytes[count - 1];
        if (((char2 & 0xC0) != 0x80) || ((char3 & 0xC0) != 0x80))
            throw malformedAt(count - 1);
        const unit = ((c & 0x0F) << 12) | ((char2 & 0x3F) << 6) | (char3 & 0x3F);
        int low;
        if (unit >= 0xD800 && unit <= 0xDBFF && lowSurrogateAt(bytes, count, utflen, low))
        {
            putCodePoint(output, used, 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00));
            return count + 3;
        }
        putCodePoint(output, used, unit);
        return count;
    }

    private static bool lowSurrogateAt(scope const(ubyte)[] bytes, size_t count, size_t utflen, out int low)
    {
        if (count + 3 > utflen)
            return false;
        const c = bytes[count] & 0xFF;
        if ((c & 0xF0) != 0xE0)
            return false;
        const char2 = bytes[count + 1];
        const char3 = bytes[count + 2];
        if (((char2 & 0xC0) != 0x80) || ((char3 & 0xC0) != 0x80))
            return false;
        low = ((c & 0x0F) << 12) | ((char2 & 0x3F) << 6) | (char3 & 0x3F);
        return low >= 0xDC00 && low <= 0xDFFF;
    }

    private static UTFDataFormatException partialCharacter() pure nothrow
    {
        return new UTFDataFormatException("malformed input: partial character at end");
    }

    private static UTFDataFormatException malformedAt(size_t offset) pure nothrow
    {
        import flint.engine.aot.text : decimal;

        return new UTFDataFormatException("malformed input around byte " ~ decimal(offset));
    }
}

// The UTF-8 byte range of `text` for the UTF-16 unit range `[off, off + len)`, as Java's `String.getChars` selects
// it. A range that starts on the low half of a supplementary character begins after it and reports a leading U+FFFD;
// one that ends on that low half ends before it and reports a trailing U+FFFD (R14). `inBounds` is false for a
// negative range or one past the text's UTF-16 length.
private struct Utf16Range
{
    size_t start;
    size_t end;
    bool leadReplacement;
    bool trailReplacement;
    bool inBounds;
}

private Utf16Range utf16Range(scope const(char)[] text, long off, long len) pure nothrow @nogc
{
    import flint.engine.aot.text : decodeUtf8;

    Utf16Range result;
    if (off < 0 || len < 0)
        return result;
    const long end = off + len;
    if (end < off) // overflow
        return result;

    size_t units;
    size_t i;
    bool started;
    size_t bodyStart;
    size_t bodyEnd;
    while (i < text.length)
    {
        const size_t codePointStart = i;
        const dchar c = decodeUtf8(text, i);
        const size_t width = c >= 0x10000 ? 2 : 1; // a supplementary character is a surrogate pair
        const size_t codePointEnd = units + width;
        if (codePointEnd <= off)
        {
            units = codePointEnd;
            continue;
        }
        if (units >= end)
            break;
        if (!started)
        {
            started = true;
            if (units < off)
            {
                result.leadReplacement = true;
                bodyStart = i; // the selected low surrogate begins after its pair
            }
            else
                bodyStart = codePointStart;
        }
        if (codePointEnd > end)
        {
            result.trailReplacement = true;
            bodyEnd = codePointStart; // the selected high surrogate ends before its pair
        }
        else
            bodyEnd = i;
        units = codePointEnd;
    }
    if (units < end)
        return result; // the range runs past the text's UTF-16 length
    result.inBounds = true;
    if (started && bodyStart < bodyEnd)
    {
        result.start = bodyStart;
        result.end = bodyEnd;
    }
    return result;
}

// The UTF-8 encoding of the UTF-16 `units`. Adjacent high and low surrogates form one supplementary code point; a
// lone half is U+FFFD (R14).
private string utf16ToUtf8(scope const(wchar)[] units) pure nothrow
{
    if (units.length == 0)
        return null;
    char[] encoded = new char[units.length * 3]; // three bytes per BMP unit is the worst case
    size_t n;
    size_t i;
    while (i < units.length)
    {
        const uint unit = units[i++];
        dchar c;
        if (unit >= 0xD800 && unit <= 0xDBFF && i < units.length && units[i] >= 0xDC00 && units[i] <= 0xDFFF)
            c = cast(dchar)(0x10000 + ((unit - 0xD800) << 10) + (units[i++] - 0xDC00));
        else if (unit >= 0xD800 && unit <= 0xDFFF)
            c = 0xFFFD;
        else
            c = cast(dchar) unit;
        if (c < 0x80)
            encoded[n++] = cast(char) c;
        else if (c < 0x800)
        {
            encoded[n++] = cast(char)(0xC0 | (c >> 6));
            encoded[n++] = cast(char)(0x80 | (c & 0x3F));
        }
        else if (c < 0x10000)
        {
            encoded[n++] = cast(char)(0xE0 | (c >> 12));
            encoded[n++] = cast(char)(0x80 | ((c >> 6) & 0x3F));
            encoded[n++] = cast(char)(0x80 | (c & 0x3F));
        }
        else
        {
            encoded[n++] = cast(char)(0xF0 | (c >> 18));
            encoded[n++] = cast(char)(0x80 | ((c >> 12) & 0x3F));
            encoded[n++] = cast(char)(0x80 | ((c >> 6) & 0x3F));
            encoded[n++] = cast(char)(0x80 | (c & 0x3F));
        }
    }
    return encoded[0 .. n].idup;
}

/// Java's `Writer`: a sink of characters (UTF-8 text in Flint).
abstract class Writer : Closeable, Flushable
{
    /// Write `text`. Java's `write(String)`, the abstract sink in Flint.
    abstract void write(scope const(char)[] text);

    /// Java's `write(String,int,int)`: `off` and `len` count UTF-16 code units. A range that splits a supplementary
    /// character writes U+FFFD for the lone half (R14); a range outside the text is rejected.
    void write(scope const(char)[] text, int off, int len)
    {
        import flint.java.lang : IndexOutOfBoundsException;

        const Utf16Range range = utf16Range(text, off, len);
        if (!range.inBounds)
            throw new IndexOutOfBoundsException("Write range exceeds the text");
        if (!range.leadReplacement && !range.trailReplacement)
        {
            write(text[range.start .. range.end]);
            return;
        }
        string replaced;
        if (range.leadReplacement)
            replaced ~= "\uFFFD";
        if (range.start < range.end)
            replaced ~= text[range.start .. range.end];
        if (range.trailReplacement)
            replaced ~= "\uFFFD";
        write(replaced);
    }

    /// Java's `write(char[])`: the whole UTF-16 array. Java's `char` is a D `wchar`; a null array is empty (R26).
    void write(scope const(wchar)[] text)
    {
        write(text, 0, cast(int) text.length);
    }

    /// Java's `write(char[],int,int)`: a UTF-16 array range, transcoded to the UTF-8 sink. Adjacent surrogates form
    /// one code point and each lone half writes U+FFFD (R14); a null array is empty (R26).
    void write(scope const(wchar)[] text, int off, int len)
    {
        import flint.java.lang : IndexOutOfBoundsException;

        if (off < 0 || len < 0 || cast(long) off + len > text.length)
            throw new IndexOutOfBoundsException("Write range exceeds the character array");
        write(utf16ToUtf8(text[off .. off + len]));
    }

    /// Write one character. Java's `write(int)` writes the low 16 bits as one UTF-16 code unit; Flint's `write(dchar)`
    /// writes one code point, and a lone surrogate or out-of-range value is U+FFFD (R14).
    void write(dchar c)
    {
        import flint.engine.aot.text : utf8;

        const text = utf8(c);
        write(text is null ? "\uFFFD" : text); // a surrogate or out-of-range code point is the replacement character
    }

    /// Write `text`; this writer.
    Writer append(scope const(char)[] text)
    {
        write(text);
        return this;
    }

    /// Java's `append(char)`: writes one UTF-16 code unit through `write(int)` and returns this writer.
    Writer append(wchar c)
    {
        write(cast(dchar) c);
        return this;
    }

    /// Flush. The default does nothing.
    void flush()
    {
    }

    /// Close. The default does nothing.
    void close()
    {
    }
}

/// A `Writer` collecting text in memory.
class StringWriter : Writer
{
    private string buffer;

    /// Starts empty.
    this() pure nothrow @nogc
    {
    }

    /// Starts empty with a buffer capacity hint. Zero is allowed; a negative size is rejected.
    this(int initialSize)
    {
        import flint.java.lang : IllegalArgumentException;

        if (initialSize < 0)
            throw new IllegalArgumentException("Negative buffer size");
    }

    alias write = Writer.write;

    override void write(scope const(char)[] text)
    {
        buffer ~= text;
    }

    /// Java's `append(char)` with a `StringWriter` result.
    override StringWriter append(wchar c)
    {
        write(cast(dchar) c);
        return this;
    }

    /// The text written.
    override string toString() const
    {
        return buffer;
    }
}

/// A `Writer` encoding UTF-8 text onto an `OutputStream`.
class OutputStreamWriter : Writer
{
    private OutputStream output;
    private bool closed_;

    /// A writer over `output`. A null stream is rejected, as Java's lock constructor does.
    this(OutputStream output)
    {
        import flint.java.lang : NullPointerException;

        if (output is null)
            throw new NullPointerException("out");
        this.output = output;
    }

    alias write = Writer.write;

    override void write(scope const(char)[] text)
    {
        if (closed_)
            throw new IOException("Stream closed");
        output.write(cast(const(ubyte)[]) text);
    }

    override void flush()
    {
        if (closed_)
            throw new IOException("Stream closed");
        output.flush();
    }

    override void close()
    {
        if (closed_)
            return;
        closed_ = true;
        try
            output.flush();
        finally
            output.close();
    }
}

/++
Java's `PrintWriter`: formatted text over a `Writer` or an `OutputStream`.

A checked write, flush or close failure is recorded in the error state instead of escaping, as Java's methods do.
Flint has no per-thread interrupt flag, so an `InterruptedIOException` is recorded there too (D-IO-2).
+/
class PrintWriter : Writer
{
    /// Java's protected `out`: the target, cleared by a successful close. `out` is a D keyword.
    protected Writer out_;
    private bool autoFlush_;
    private bool trouble_;

    /// A print writer over `target`, without automatic flushing. A null writer is rejected.
    this(Writer target)
    {
        this(target, false);
    }

    /// A print writer over `target`; `autoFlush` flushes after every `println`.
    this(Writer target, bool autoFlush)
    {
        import flint.java.lang : NullPointerException;

        if (target is null)
            throw new NullPointerException("out");
        out_ = target;
        autoFlush_ = autoFlush;
    }

    /// A print writer over `output`, encoding UTF-8. A null stream is rejected.
    this(OutputStream output)
    {
        import flint.java.lang : NullPointerException;

        if (output is null)
            throw new NullPointerException("out");
        out_ = new OutputStreamWriter(output);
    }

    alias write = Writer.write;

    override void write(scope const(char)[] text)
    {
        if (out_ is null)
        {
            trouble_ = true;
            return;
        }
        try
            out_.write(text);
        catch (IOException)
            trouble_ = true;
    }

    override void write(scope const(char)[] text, int off, int len)
    {
        if (out_ is null)
        {
            trouble_ = true;
            return;
        }
        try
            out_.write(text, off, len);
        catch (IOException)
            trouble_ = true;
    }

    override void write(scope const(wchar)[] text, int off, int len)
    {
        if (out_ is null)
        {
            trouble_ = true;
            return;
        }
        try
            out_.write(text, off, len);
        catch (IOException)
            trouble_ = true;
    }

    override void write(dchar c)
    {
        if (out_ is null)
        {
            trouble_ = true;
            return;
        }
        try
            out_.write(c);
        catch (IOException)
            trouble_ = true;
    }

    /// Java's `print(String)`.
    void print(scope const(char)[] text)
    {
        write(text);
    }

    /// Java's `print(char[])`: one UTF-16 unit array; a null array is empty (R26).
    void print(scope const(wchar)[] text)
    {
        write(text);
    }

    /// Java's `print(char)`: one UTF-16 code unit through the single-character write (R14).
    void print(C)(C c) if (is(C == wchar))
    {
        write(cast(dchar) c);
    }

    /// Java's `print` of any value: `String.valueOf(value)`.
    void print(T)(T value) if (!is(T : const(char)[]) && !is(T : const(wchar)[]) && !is(T == wchar))
    {
        import flint.java.lang : valueOf;

        write(valueOf(value));
    }

    /// Java's `println()`: the platform line separator.
    void println()
    {
        newLine();
    }

    /// Java's `println(String)`.
    void println(scope const(char)[] text)
    {
        print(text);
        newLine();
    }

    /// Java's `println(char[])`; a null array is empty (R26).
    void println(scope const(wchar)[] text)
    {
        print(text);
        newLine();
    }

    /// Java's `println` of any value.
    void println(T)(T value) if (!is(T : const(char)[]) && !is(T : const(wchar)[]))
    {
        print(value);
        newLine();
    }

    private void newLine()
    {
        import flint.java.lang : System;

        if (out_ is null)
        {
            trouble_ = true;
            return;
        }
        try
        {
            out_.write(System.lineSeparator());
            if (autoFlush_)
                out_.flush();
        }
        catch (IOException)
            trouble_ = true;
    }

    /// Java's `append(CharSequence)`.
    override PrintWriter append(scope const(char)[] text)
    {
        write(text);
        return this;
    }

    /// Java's `append(char)`: one UTF-16 code unit through the single-character write (R14).
    override PrintWriter append(wchar c)
    {
        write(cast(dchar) c);
        return this;
    }

    /// Java's `checkError`: flush while open, then this writer's or a nested writer's error.
    bool checkError()
    {
        if (out_ !is null)
            flush();
        if (auto nested = cast(PrintWriter) out_)
            return nested.checkError();
        return trouble_;
    }

    /// Java's protected `setError`.
    protected void setError()
    {
        trouble_ = true;
    }

    /// Java's protected `clearError`.
    protected void clearError()
    {
        trouble_ = false;
    }

    override void flush()
    {
        if (out_ is null)
        {
            trouble_ = true;
            return;
        }
        try
            out_.flush();
        catch (IOException)
            trouble_ = true;
    }

    override void close()
    {
        if (out_ is null)
            return;
        try
        {
            out_.close();
            out_ = null;
        }
        catch (IOException)
            trouble_ = true;
    }
}

/// An `InputStream` over bytes in memory.
class ByteArrayInputStream : InputStream
{
    private enum int maxTransferSize = 128 * 1024;

    /// Java's `buf`: the caller's bytes, not copied. A D `const(ubyte)` slice under R26.
    protected const(ubyte)[] buf;

    /// The index of the next byte to read.
    protected int pos;

    /// The mark index; `reset` returns here. Zero before any mark or a plain constructor.
    /// Java names it `mark`, which D cannot share with the `mark(int)` method.
    protected int markpos;

    /// One past the last readable byte.
    protected int count;

    alias read = InputStream.read;
    alias readNBytes = InputStream.readNBytes;

    /// Read from `bytes`, which the stream does not copy.
    this(const(ubyte)[] bytes) pure nothrow @nogc
    {
        buf = bytes;
        count = cast(int) bytes.length;
    }

    /// Read at most `length` bytes from `bytes` starting at `offset`.
    this(const(ubyte)[] bytes, int offset, int length) pure nothrow @nogc
    {
        buf = bytes;
        pos = offset;
        const end = offset + length;
        count = end < cast(int) bytes.length ? end : cast(int) bytes.length;
        markpos = offset;
    }

    override int read()
    {
        return pos < count ? (buf[pos++] & 0xff) : -1;
    }

    override int read(scope ubyte[] buffer, int offset, int length)
    {
        checkReadRange(buffer.length, offset, length);
        if (pos >= count)
            return -1;
        const available = count - pos;
        if (length > available)
            length = available;
        if (length <= 0)
            return 0;
        copyRange(buffer, offset, buf, pos, length);
        pos += length;
        return length;
    }

    override ubyte[] readAllBytes()
    {
        auto result = buf[pos .. count].dup;
        pos = count;
        return result;
    }

    override int readNBytes(scope ubyte[] buffer, int offset, int length)
    {
        const n = read(buffer, offset, length);
        return n == -1 ? 0 : n;
    }

    /// Copy the remaining bytes to `target` but keep this stream open.
    override long transferTo(OutputStream target)
    {
        const remaining = count - pos;
        if (remaining > 0)
        {
            import flint.java.lang : NullPointerException;

            if (target is null)
                throw new NullPointerException("out");
            int written;
            while (written < remaining)
            {
                const chunk = remaining - written < maxTransferSize ? remaining - written : maxTransferSize;
                target.write(buf, pos, chunk);
                pos += chunk;
                written += chunk;
            }
        }
        return remaining;
    }

    override long skip(long amount) pure nothrow @nogc
    {
        long skipped = count - pos;
        if (amount < skipped)
            skipped = amount < 0 ? 0 : amount;
        pos += cast(int) skipped;
        return skipped;
    }

    /// How many bytes remain.
    override int available() pure nothrow @nogc
    {
        return count - pos;
    }

    /// A byte-array source always supports mark and reset.
    override bool markSupported() pure nothrow @nogc
    {
        return true;
    }

    /// Record the current position; the read-ahead limit has no meaning here.
    override void mark(int)
    {
        markpos = pos;
    }

    /// Return to the last mark, initially zero or the ranged constructor's offset.
    override void reset() pure nothrow @nogc
    {
        pos = markpos;
    }
}

/// Java's `SequenceInputStream`: the bytes of two streams in order.
class SequenceInputStream : InputStream
{
    private InputStream in_;
    private InputStream[2] sources_;
    private size_t nextIndex_;
    private bool hasNext_;

    alias read = InputStream.read;

    /// The bytes of `s1`, then `s2`. A null first stream is rejected at once.
    this(InputStream s1, InputStream s2)
    {
        sources_[0] = s1;
        sources_[1] = s2;
        hasNext_ = true;
        nextStream();
    }

    private void nextStream()
    {
        import flint.java.lang : NullPointerException;

        if (in_ !is null)
            in_.close();
        if (!hasNext_)
        {
            in_ = null;
            return;
        }
        in_ = sources_[nextIndex_];
        ++nextIndex_;
        hasNext_ = nextIndex_ < sources_.length;
        if (in_ is null)
            throw new NullPointerException("stream");
    }

    override int read()
    {
        for (;;)
        {
            if (in_ is null)
                return -1;
            const value = in_.read();
            if (value != -1)
                return value;
            nextStream();
        }
    }

    override int read(scope ubyte[] buffer, int offset, int length)
    {
        checkReadRange(buffer.length, offset, length);
        if (in_ is null)
            return -1;
        if (length == 0)
            return 0;
        do
        {
            const count = in_.read(buffer, offset, length);
            if (count > 0)
                return count;
            nextStream();
        }
        while (in_ !is null);
        return -1;
    }

    /// The current stream's available count, or zero when none remains.
    override int available()
    {
        if (in_ is null)
            return 0;
        try
            return in_.available();
        catch (IOException)
            return 0;
    }

    /// Close the current stream and every stream that follows it.
    override void close()
    {
        while (in_ !is null)
        {
            in_.close();
            if (!hasNext_)
            {
                in_ = null;
                break;
            }
            in_ = sources_[nextIndex_];
            ++nextIndex_;
            hasNext_ = nextIndex_ < sources_.length;
        }
    }

    /// Copy the sequence to `target`; zero when it is already exhausted.
    override long transferTo(OutputStream target)
    {
        if (in_ is null)
            return 0;
        import flint.java.lang : NullPointerException;

        if (target is null)
            throw new NullPointerException("out");
        enum int chunkSize = 8192;
        ubyte[chunkSize] chunk;
        long transferred;
        for (;;)
        {
            const count = read(chunk[]);
            if (count < 0)
                break;
            target.write(chunk[0 .. count], 0, count);
            transferred += count;
        }
        return transferred;
    }
}

/// Java's `UnixFileSystem.normalize`: collapse runs of `/` and drop a trailing `/`, except for the root.
private string normalizePathname(string pathname) pure nothrow
{
    size_t length;
    char previous = '\0';
    foreach (const char c; pathname)
    {
        if (previous == '/' && c == '/')
            continue;
        length++;
        previous = c;
    }
    if (length > 1 && previous == '/')
        length--;
    if (length == pathname.length)
        return pathname;

    char[] normalized = new char[pathname.length];
    size_t index;
    previous = '\0';
    foreach (const char c; pathname)
    {
        if (previous == '/' && c == '/')
            continue;
        normalized[index++] = c;
        previous = c;
    }
    return normalized[0 .. length].idup;
}

/// Java's `UnixFileSystem.resolve(parent, child)`: `child` under `parent`, keeping a rooted child in place.
private string resolvePathname(string parent, string child) pure nothrow
{
    if (child.length == 0)
        return parent;
    if (child[0] == '/')
    {
        if (parent == "/")
            return child;
        return trimSeparator(parent ~ child);
    }
    return trimSeparator(parent == "/" ? parent ~ child : parent ~ "/" ~ child);
}

/// Java's `UnixFileSystem.trimSeparator`: drop one trailing `/`, never from the root.
private string trimSeparator(string path) pure nothrow @nogc
{
    return path.length > 1 && path[$ - 1] == '/' ? path[0 .. $ - 1] : path;
}

/// Java's `File`: a filesystem path.
class File
{
    private string path_;

    /// The file at `pathname`.
    this(string pathname) pure nothrow
    {
        path_ = normalizePathname(pathname);
    }

    /// The file `child` inside `parent`; a null parent leaves `child` bare, an empty one uses the root.
    this(string parent, string child) pure nothrow
    {
        const normalizedChild = normalizePathname(child);
        if (parent is null)
            path_ = normalizedChild;
        else if (parent.length == 0)
            path_ = resolvePathname("/", normalizedChild);
        else
            path_ = resolvePathname(normalizePathname(parent), normalizedChild);
    }

    /// The file `child` inside the already normalized `parent`.
    this(File parent, string child) pure nothrow
    {
        const normalizedChild = normalizePathname(child);
        if (parent is null)
            path_ = normalizedChild;
        else if (parent.path_.length == 0)
            path_ = resolvePathname("/", normalizedChild);
        else
            path_ = resolvePathname(parent.path_, normalizedChild);
    }

    /// The normalized pathname.
    string getPath() const pure nothrow @nogc
    {
        return path_;
    }

    /// The last path component.
    string getName() const pure nothrow @nogc
    {
        size_t start;
        foreach (i, c; path_)
            if (c == '/')
                start = i + 1;
        return path_[start .. $];
    }

    /// The parent path, or null.
    string getParent() const pure nothrow @nogc
    {
        size_t end = path_.length;
        while (end > 0 && path_[end - 1] != '/')
            end--;
        if (end == 0)
            return null;
        if (end == 1)
            return path_.length == 1 ? null : "/";
        return path_[0 .. end - 1];
    }

    /// Whether `other` is a `File` with the same pathname.
    bool equals(Object other)
    {
        import flint.engine.aot.objects : objectToString;

        return other is this || (other !is null && File.classinfo.isBaseOf(other.classinfo)
                && path_ == objectToString(other));
    }

    /// Java's `String.hashCode` of the pathname.
    int hashCode() const pure nothrow @nogc
    {
        import flint.java.lang : stringHashCode;

        return stringHashCode(path_);
    }

    /// Java's pathname order: the pathname strings compared by UTF-16 code unit.
    int compareTo(File other) pure
    {
        if (other is null)
            rejectNullIoArgument();
        return comparePathnames(path_, other.path_);
    }

    /// `==` through an `Object` reference calls `equals`.
    override bool opEquals(Object other)
    {
        return equals(other);
    }

    /// `==` between two `File` values compares pathnames.
    bool opEquals(File other)
    {
        return this is other || (other !is null && path_ == other.path_);
    }

    /// Associative arrays hash the pathname.
    override size_t toHash() @safe nothrow
    {
        return cast(size_t) cast(uint) hashCode();
    }

    /// `<` orders by `compareTo`; an unrelated object is unordered.
    override int opCmp(Object other)
    {
        import flint.engine.aot.objects : objectToString;

        if (other is null || !File.classinfo.isBaseOf(other.classinfo))
            return 0;
        return comparePathnames(path_, objectToString(other));
    }

    /// The absolute path.
    string getAbsolutePath() const
    {
        import flint.engine.aot.host : absolutePath, currentDirectory;

        if (path_.length == 0)
        {
            const working = currentDirectory();
            return working is null ? "" : working;
        }
        return absolutePath(path_);
    }

    /// Whether the path exists.
    bool exists() const
    {
        import flint.engine.aot.host : fileFacts;

        return fileFacts(path_).exists;
    }

    /// Whether the path is a regular file.
    bool isFile() const
    {
        import flint.engine.aot.host : fileFacts;

        return fileFacts(path_).regular;
    }

    /// Whether the path is a directory.
    bool isDirectory() const
    {
        import flint.engine.aot.host : fileFacts;

        return fileFacts(path_).directory;
    }

    /// Whether the file can be read: it exists. (D offers no portable access check without opening the file.)
    bool canRead() const
    {
        return exists();
    }

    /// The size in bytes; 0 when it does not exist.
    long length() const
    {
        import flint.engine.aot.host : fileFacts;

        const facts = fileFacts(path_);
        return facts.regular ? facts.size : 0;
    }

    /// Milliseconds since the epoch of the last modification; 0 when it does not exist.
    long lastModified() const
    {
        import flint.engine.aot.host : fileFacts, modifiedMillis;

        const facts = fileFacts(path_);
        return facts.exists ? modifiedMillis(facts) : 0;
    }

    /// The path.
    override string toString() const
    {
        return getPath();
    }
}

/// An `InputStream` over a file's bytes, read at construction.
class FileInputStream : ByteArrayInputStream
{
    /// Open `file`. Throws `FileNotFoundException` when it is missing, not a regular file, or cannot be read.
    this(File file)
    {
        import flint.engine.aot.host : describe, FileError, readFile;

        if (!file.isFile())
            throw new FileNotFoundException(file.getPath() ~ " (No such file or directory)");
        FileError error;
        auto bytes = readFile(file.getPath(), error);
        if (bytes is null)
            throw new FileNotFoundException(file.getPath() ~ " (" ~ describe(error) ~ ")");
        super(bytes);
    }
}

/// Java's checked `EOFException`: an end of file was reached unexpectedly.
class EOFException : IOException
{
    /// `message`, or null.
    this(string message = null, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, null, file, line);
    }
}

/// Java's checked `UTFDataFormatException`: malformed modified UTF-8, or text too long for `writeUTF`.
class UTFDataFormatException : IOException
{
    /// `message`, or null.
    this(string message = null, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, null, file, line);
    }
}
