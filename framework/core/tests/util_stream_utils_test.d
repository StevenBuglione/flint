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
 * Ported from spring-framework v7.1.0, spring-core/src/test/java/org/springframework/util/StreamUtilsTests.java.
 * Modified by the Flint authors.
 */
module flint.util.stream_utils_test;

import flint.java.io : ByteArrayInputStream, ByteArrayOutputStream, IOException, InputStream;
import flint.util : StreamUtils;
import flint.util.test_support : expectThrows;

@safe:

private ubyte[] sampleBytes()
{
    auto bytes = new ubyte[StreamUtils.BUFFER_SIZE + 10];
    foreach (i, ref value; bytes)
        value = cast(ubyte) i;
    return bytes;
}

private class TestInput : ByteArrayInputStream
{
    int closes;
    int bulkReads;
    bool zeroNextBulk;

    this(const(ubyte)[] bytes)
    {
        super(bytes);
    }

    alias read = ByteArrayInputStream.read;

    override int read(scope ubyte[] buffer)
    {
        ++bulkReads;
        if (zeroNextBulk)
        {
            zeroNextBulk = false;
            return 0;
        }
        return super.read(buffer);
    }

    override void close()
    {
        ++closes;
    }
}

private class TestOutput : ByteArrayOutputStream
{
    int closes;
    int flushes;
    int bulkWrites;

    override void write(scope const(ubyte)[] bytes)
    {
        ++bulkWrites;
        super.write(bytes);
    }

    override void close()
    {
        ++closes;
    }

    override void flush()
    {
        ++flushes;
    }
}

@("copyToByteArray")
unittest
{
    auto bytes = sampleBytes();
    auto input = new TestInput(bytes);
    assert(StreamUtils.copyToByteArray(input) == bytes && input.closes == 0);
    auto empty = StreamUtils.copyToByteArray(cast(InputStream) null);
    assert(empty !is null && empty.length == 0);
}

@("copyBytes")
unittest
{
    auto bytes = sampleBytes();
    auto output = new TestOutput;
    StreamUtils.copy(bytes, output);
    assert(output.toByteArray() == bytes && output.flushes == 1 && output.closes == 0);
}

@("copyStream")
unittest
{
    auto bytes = sampleBytes();
    auto input = new TestInput(bytes);
    auto output = new TestOutput;
    assert(StreamUtils.copy(input, output) == bytes.length);
    assert(output.toByteArray() == bytes && output.bulkWrites == 2);
    assert(output.flushes == 1 && output.closes == 0 && input.closes == 0);
}

@("nonClosingInputStream")
unittest
{
    auto input = new TestInput([1, 2, 3, 4]);
    auto wrapped = StreamUtils.nonClosing(input);
    ubyte[2] buffer;
    assert(wrapped.read() == 1 && wrapped.read(buffer[]) == 2 && buffer == [2, 3]);
    assert(wrapped.readAllBytes() == [4] && input.bulkReads == 3);
    wrapped.close();
    assert(input.closes == 0 && StreamUtils.nonClosing(wrapped) is wrapped);
}

@("nonClosingOutputStream")
unittest
{
    auto output = new TestOutput;
    auto wrapped = StreamUtils.nonClosing(output);
    wrapped.write(1);
    wrapped.write([2, 3]);
    wrapped.write([4, 5, 6], 1, 2);
    wrapped.flush();
    wrapped.close();
    assert(output.toByteArray() == [1, 2, 3, 5, 6] && output.bulkWrites == 2);
    assert(output.flushes == 1 && output.closes == 0);
    assert(StreamUtils.nonClosing(wrapped) is wrapped);
}

@("nonFlushingOutputStream")
unittest
{
    auto output = new TestOutput;
    auto wrapped = StreamUtils.nonFlushing(output);
    wrapped.write(1);
    wrapped.write([2, 3]);
    wrapped.write([4, 5, 6], 1, 2);
    wrapped.flush();
    wrapped.close();
    assert(output.toByteArray() == [1, 2, 3, 5, 6] && output.bulkWrites == 2);
    assert(output.flushes == 0 && output.closes == 0);
    assert(StreamUtils.nonFlushing(wrapped) is wrapped && StreamUtils.nonClosing(wrapped) is wrapped);
}

@("drain counts bytes and leaves the source open")
unittest
{
    auto bytes = sampleBytes();
    auto input = new TestInput(bytes);
    assert(StreamUtils.drain(input) == bytes.length);
    assert(input.read() == -1 && input.closes == 0);
    assert(StreamUtils.drain(null) == 0);
}

@("a zero-byte bulk read falls back to one byte and makes progress")
unittest
{
    auto input = new TestInput([10, 20]);
    input.zeroNextBulk = true;
    auto output = new TestOutput;
    assert(StreamUtils.copy(input, output) == 2);
    assert(output.toByteArray() == [10, 20]);
}

@("an empty input is independent and reports reads after close")
unittest
{
    auto input = StreamUtils.emptyInput();
    auto another = StreamUtils.emptyInput();
    assert(input !is another && input.read() == -1);
    assert(input.read(null) == 0);
    input.close();
    expectThrows!IOException(() { input.read(); });
    assert(another.read() == -1);
}
