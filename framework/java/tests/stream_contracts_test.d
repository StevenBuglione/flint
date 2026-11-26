// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for the shared close and flush interfaces. */
module flint.java.stream_contracts_test;

import flint.java.io : Closeable, Flushable, IOException;
import flint.java.io.closeable : CloseableLeaf = Closeable;
import flint.java.io.flushable : FlushableLeaf = Flushable;
import flint.java.lang : AutoCloseable;

@safe:

private final class RecordingResource : Closeable, Flushable
{
    int flushCount;
    IOException failure;

    this(IOException failure)
    {
        this.failure = failure;
    }

    override void flush()
    {
        ++flushCount;
    }

    override void close()
    {
        throw failure;
    }
}

@("Closeable, AutoCloseable and Flushable preserve dispatch and exception identity")
unittest
{
    static assert(is(Closeable == CloseableLeaf));
    static assert(is(Flushable == FlushableLeaf));

    auto expected = new IOException("close failure");
    auto target = new RecordingResource(expected);
    Closeable resource = target;
    AutoCloseable close = resource;
    Flushable buffered = target;

    buffered.flush();
    assert(target.flushCount == 1);

    IOException actual;
    try
        close.close();
    catch (IOException failure)
        actual = failure;
    assert(actual is expected);
}
