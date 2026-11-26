/*
 * Copyright 2002-present the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Ported from spring-framework v7.1.0, spring-core/src/main/java/org/springframework/util/StreamUtils.java.
 * Modified by the Flint authors.
 */
module flint.util.stream_utils;

import flint.java.io : IOException, InputStream, OutputStream;
import flint.java.lang : IllegalArgumentException;

@safe:

/// Byte-stream operations that leave the affected streams open.
abstract class StreamUtils
{
    enum int BUFFER_SIZE = 8192;

    static ubyte[] copyToByteArray(InputStream input)
    {
        auto bytes = input is null ? null : input.readAllBytes();
        return bytes is null ? emptyByteArray() : bytes;
    }

    static void copy(scope const(ubyte)[] bytes, OutputStream output)
    {
        requireArgument(bytes !is null, "No input byte array specified");
        requireArgument(output !is null, "No OutputStream specified");
        output.write(bytes);
        output.flush();
    }

    static int copy(InputStream input, OutputStream output)
    {
        requireArgument(input !is null, "No InputStream specified");
        requireArgument(output !is null, "No OutputStream specified");
        const count = transfer(input, output);
        output.flush();
        return cast(int) count;
    }

    static int drain(InputStream input)
    {
        return input is null ? 0 : cast(int) transfer(input, null);
    }

    deprecated("Use the java.io null input stream when available") static InputStream emptyInput()
    {
        return new EmptyInputStream;
    }

    static InputStream nonClosing(InputStream input)
    {
        requireArgument(input !is null, "No InputStream specified");
        return cast(NonClosingInputStream) input !is null ? input : new NonClosingInputStream(input);
    }

    static OutputStream nonClosing(OutputStream output)
    {
        requireArgument(output !is null, "No OutputStream specified");
        return cast(NonClosingOutputStream) output !is null ? output : new NonClosingOutputStream(output);
    }

    static OutputStream nonFlushing(OutputStream output)
    {
        requireArgument(output !is null, "No OutputStream specified");
        return cast(NonFlushingOutputStream) output !is null ? output : new NonFlushingOutputStream(output);
    }

    private static ulong transfer(InputStream input, OutputStream output)
    {
        auto buffer = new ubyte[BUFFER_SIZE];
        ulong total;
        for (;;)
        {
            auto count = input.read(buffer);
            if (count == 0)
            {
                auto next = input.read();
                if (next < 0)
                    return total;
                buffer[0] = cast(ubyte) next;
                count = 1;
            }
            if (count < 0)
                return total;
            if (output !is null)
                output.write(buffer, 0, count);
            total += count;
        }
    }
}

private void requireArgument(bool present, string message)
{
    if (!present)
        throw new IllegalArgumentException(message);
}

private ubyte[] emptyByteArray()
{
    auto storage = new ubyte[1];
    return storage[0 .. 0];
}

private final class EmptyInputStream : InputStream
{
    private bool closed;

    override int read()
    {
        ensureOpen();
        return -1;
    }

    override int read(scope ubyte[] buffer)
    {
        ensureOpen();
        return buffer.length == 0 ? 0 : -1;
    }

    override ubyte[] readAllBytes()
    {
        ensureOpen();
        return emptyByteArray();
    }

    override void close()
    {
        closed = true;
    }

    private void ensureOpen()
    {
        if (closed)
            throw new IOException("Stream closed");
    }
}

private final class NonClosingInputStream : InputStream
{
    private InputStream input;

    this(InputStream input)
    {
        this.input = input;
    }

    override int read()
    {
        return input.read();
    }

    override int read(scope ubyte[] buffer)
    {
        return input.read(buffer);
    }

    override ubyte[] readAllBytes()
    {
        return input.readAllBytes();
    }
}

private class NonClosingOutputStream : OutputStream
{
    private OutputStream output;

    this(OutputStream output)
    {
        this.output = output;
    }

    override void write(int value)
    {
        output.write(value);
    }

    override void write(scope const(ubyte)[] bytes)
    {
        output.write(bytes);
    }

    override void write(scope const(ubyte)[] bytes, int offset, int length)
    {
        output.write(bytes, offset, length);
    }

    override void flush()
    {
        output.flush();
    }
}

private final class NonFlushingOutputStream : NonClosingOutputStream
{
    this(OutputStream output)
    {
        super(output);
    }

    override void flush()
    {
    }
}
