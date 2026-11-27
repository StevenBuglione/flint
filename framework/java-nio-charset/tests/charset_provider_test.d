// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module charset_provider_test;

import flint.java.lang : UnsupportedOperationException;
import flint.java.nio.charset : Charset, StandardCharsets;
import flint.java.nio.charset.spi.charsetprovider : CharsetProvider;
import flint.java.util : Iterator, NoSuchElementException;

@safe:

private final class SliceCharsetIterator : Iterator!Charset
{
    private const(Charset)[] items;
    private size_t index;

    this(const(Charset)[] items) pure nothrow @nogc
    {
        this.items = items;
    }

    override bool hasNext() pure nothrow @nogc
    {
        return index < items.length;
    }

    override Charset next()
    {
        if (index >= items.length)
            throw new NoSuchElementException;
        return items[index++];
    }

    override void remove()
    {
        throw new UnsupportedOperationException;
    }
}

private final class SampleCharsetProvider : CharsetProvider
{
    private static immutable Charset[2] supported = [
        StandardCharsets.UTF_8, StandardCharsets.US_ASCII,
    ];

    this()
    {
        super();
    }

    override Iterator!Charset charsets()
    {
        return new SliceCharsetIterator(supported[]);
    }

    override Charset charsetForName(string charsetName)
    {
        if (charsetName == "UTF-8" || charsetName == "utf8")
            return StandardCharsets.UTF_8;
        if (charsetName == "US-ASCII" || charsetName == "ASCII")
            return StandardCharsets.US_ASCII;
        return Charset.init;
    }
}

unittest
{
    // CharsetProvider is abstract and cannot be instantiated directly.
    static assert(!__traits(compiles, new CharsetProvider()));

    CharsetProvider provider = new SampleCharsetProvider();

    // Canonical names and aliases resolve; unknown or null/empty names return Charset.init.
    assert(provider.charsetForName("UTF-8") == StandardCharsets.UTF_8);
    assert(provider.charsetForName("utf8") == StandardCharsets.UTF_8);
    assert(provider.charsetForName("US-ASCII") == StandardCharsets.US_ASCII);
    assert(provider.charsetForName("ASCII") == StandardCharsets.US_ASCII);
    assert(provider.charsetForName("X-UNKNOWN") == Charset.init);
    assert(provider.charsetForName("") == Charset.init);
    assert(provider.charsetForName(null) == Charset.init);

    // Each charsets() call yields a fresh iterator over the provider's charsets.
    auto first = provider.charsets();
    assert(first.hasNext());
    assert(first.next() == StandardCharsets.UTF_8);
    assert(first.hasNext());
    assert(first.next() == StandardCharsets.US_ASCII);
    assert(!first.hasNext());

    bool threwNoSuch = false;
    try
    {
        first.next();
    }
    catch (NoSuchElementException)
    {
        threwNoSuch = true;
    }
    assert(threwNoSuch);

    auto second = provider.charsets();
    assert(second.hasNext());
    assert(second.next() == StandardCharsets.UTF_8);
}
