module inputskip_test;

import flint.java.io : ByteArrayInputStream, IOException, InputStream;
import flint.java.lang : IndexOutOfBoundsException;

@safe:

private final class TrackingRange : InputStream
{
    alias read = InputStream.read;

    int[5] requests;
    size_t scratchLength;
    size_t requestCount;
    int remaining = 4_101;

    override int read()
    {
        assert(false, "skip must dispatch the ranged read");
    }

    override int read(scope ubyte[] target, int offset, int length)
    {
        assert(offset == 0 && length <= target.length);
        scratchLength = target.length;
        requests[requestCount++] = length;
        if (remaining == 0)
            return -1;
        const count = length < remaining ? length : remaining;
        remaining -= count;
        return count;
    }
}

private final class FailOnce : InputStream
{
    alias read = InputStream.read;

    private int failAt;
    private int next;

    this(int failAt)
    {
        this.failAt = failAt;
    }

    override int read()
    {
        const index = next++;
        if (index == failAt)
            throw new IOException("source");
        return index >= 5 ? -1 : 128 + index;
    }
}

@("skip uses the virtual ranged read in bounded chunks and stops at EOF")
unittest
{
    auto input = new TrackingRange;
    assert(input.skip(-1) == 0 && input.skip(0) == 0 && input.requestCount == 0);
    assert(input.skip(long.max) == 4_101);
    assert(input.requests[0 .. input.requestCount] == [2048, 2048, 2048, 2048]);
    assert(input.scratchLength == 2048);
    input = new TrackingRange;
    assert(input.skip(9) == 9 && input.scratchLength == 9);
    assert(input.requestCount == 1);
}

@("byte array skip advances exactly the available bytes")
unittest
{
    auto input = new ByteArrayInputStream([193, 214]);
    assert(input.skip(-10) == 0 && input.read() == 193);
    assert(input.skip(10) == 1 && input.read() == -1);
    ubyte[] empty;
    assert(input.read(empty, 0, 0) == -1 && input.skip(10) == 0);
}

@("ranged read returns partial bytes after a late checked exception")
unittest
{
    ubyte[5] storage = 7;
    auto input = new FailOnce(2);
    assert(input.read(storage[], 1, 3) == 2);
    assert(storage[] == [7, 128, 129, 7, 7]);
    assert(input.read() == 131);

    try
    {
        cast(void)(new FailOnce(0)).read(storage[], 1, 3);
        assert(false, "missing first-byte IOException");
    }
    catch (IOException failure)
    {
        assert(failure.getMessage() == "source");
    }
}

@("invalid ranges fail before reading while empty valid ranges are harmless")
unittest
{
    ubyte[5] storage = 7;
    auto input = new FailOnce(5);
    try
    {
        cast(void) input.read(storage[], 2, int.max);
        assert(false, "missing IndexOutOfBoundsException");
    }
    catch (IndexOutOfBoundsException)
    {
        assert(input.read(storage[], 5, 0) == 0);
        assert(input.read() == 128);
        assert(storage[] == [7, 7, 7, 7, 7]);
    }
}

@("default whole-array read dispatches an inherited ranged override")
unittest
{
    auto input = new TrackingRange;
    ubyte[3] target;
    assert(input.read(target[]) == 3);
    assert(input.requestCount == 1 && input.requests[0] == 3);
}

@("byte-array ranged read copies an overlapping live backing array")
unittest
{
    ubyte[] backing = [1, 2, 3, 4, 5];
    auto input = new ByteArrayInputStream(backing);
    assert(input.read(backing, 1, 3) == 3);
    assert(backing == [1, 1, 2, 3, 5]);
    assert(input.read() == 3);

    backing = [1, 2, 3, 4, 5];
    input = new ByteArrayInputStream(backing);
    assert(input.skip(1) == 1);
    assert(input.read(backing, 0, 3) == 3);
    assert(backing == [2, 3, 4, 4, 5]);
    assert(input.read() == 5);

    backing = [1, 2, 3];
    input = new ByteArrayInputStream(backing);
    assert(input.read(backing, 0, 3) == 3 && backing == [1, 2, 3]);
}
