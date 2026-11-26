module properties_stream_test;

import flint.java.io : ByteArrayInputStream, IOException, InputStream;
import flint.java.lang : IllegalArgumentException, NullPointerException;
import flint.java.util : Properties;
import std.exception : assertThrown;

@safe:

@("Properties byte loading interprets every octet as Latin-1 and leaves the stream open") unittest
{
    auto input = new ChunkedInput([
        cast(const(ubyte)[]) "byte=\xc3\xa9\r\nsplit=\xe9\\\r",
        cast(const(ubyte)[]) "\n  \xe0\rafter=2",
    ]);
    auto properties = new Properties;
    properties.load(input);
    assert(properties.getProperty("byte") == "\u00c3\u00a9");
    assert(properties.getProperty("split") == "\u00e9\u00e0");
    assert(properties.getProperty("after") == "2");
    assert(!input.closed);
    assertThrown!NullPointerException(properties.load(cast(InputStream) null));
}

@("Properties byte loading commits the prefix returned before a later read failure") unittest
{
    auto input = new ChunkedInput([cast(const(ubyte)[]) "settled=ok\nunsettled=partial"], true);
    auto properties = new Properties;
    assertThrown!IOException(properties.load(input));
    assert(properties.getProperty("settled") == "ok");
    assert(!properties.containsKey("unsettled") && !input.closed);

    // Java reads ahead when the newline is the last buffered byte.
    auto boundary = new ChunkedInput([cast(const(ubyte)[]) "atBoundary=uncommitted\n"], true);
    assertThrown!IOException(properties.load(boundary));
    assert(!properties.containsKey("atBoundary") && !boundary.closed);
}

@("Properties continuation refills at the final CR of a full buffer and after single-byte reads") unittest
{
    enum bufferSize = 8192;
    auto bytes = new ubyte[bufferSize + 2];
    bytes[] = 'x';
    bytes[0 .. 2] = [cast(ubyte) 'a', '='];
    bytes[bufferSize - 2 .. $] = [cast(ubyte) '\\', '\r', '\n', 'z'];
    auto properties = new Properties;
    properties.load(new ByteArrayInputStream(bytes));
    auto joined = properties.getProperty("a");
    assert(properties.size() == 1 && joined.length == bufferSize - 3);
    assert(joined[0 .. $ - 1] == cast(const(char)[]) bytes[2 .. bufferSize - 2]);
    assert(joined[$ - 1] == 'z');

    auto split = cast(const(ubyte)[]) "b=p\\\r\n\tq";
    auto chunks = new const(ubyte)[][split.length];
    foreach (index, ref chunk; chunks)
        chunk = split[index .. index + 1];
    properties.load(new ChunkedInput(chunks));
    assert(properties.getProperty("b") == "pq");
}

@("Properties recognizes comments after a continuation only while the logical line is empty") unittest
{
    enum text = "\\\n#ignored=1\na=b\\\n#value=1";
    auto properties = new Properties;
    properties.load(new ByteArrayInputStream(cast(ubyte[]) text.dup));
    assert(properties.size() == 1 && properties.getProperty("a") == "b#value=1");
}

@("Properties normalizes escaped UTF-16 pairs and replaces isolated surrogates") unittest
{
    enum source = "paired=\\uD83D\\uDE00\nloneHigh=\\uD800!\nloneLow=\\uDC00\ntrailing=x\\";
    auto properties = new Properties;
    properties.load(new ByteArrayInputStream(cast(ubyte[]) source.dup));
    assert(properties.getProperty("paired") == "\U0001f600");
    assert(properties.getProperty("loneHigh") == "\ufffd!");
    assert(properties.getProperty("loneLow") == "\ufffd");
    assert(properties.getProperty("trailing") == "x");
    assertThrown!IllegalArgumentException(
            properties.load(new ByteArrayInputStream(cast(ubyte[]) "bad=\\uD83D\\uDE0Z".dup)));
}

private final class ChunkedInput : InputStream
{
    private const(ubyte)[][] chunks;
    private bool failAtEnd;
    private size_t cursor;
    bool closed;

    this(const(ubyte)[][] chunks, bool failAtEnd = false)
    {
        this.chunks = chunks;
        this.failAtEnd = failAtEnd;
    }

    override int read()
    {
        assert(0, "Properties must use bulk reads");
    }

    override int read(scope ubyte[] buffer)
    {
        if (cursor == chunks.length)
        {
            if (failAtEnd)
                throw new IOException("late failure");
            return -1;
        }
        const chunk = chunks[cursor++];
        buffer[0 .. chunk.length] = chunk;
        return cast(int) chunk.length;
    }

    override void close()
    {
        closed = true;
    }
}
