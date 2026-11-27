// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module charset_provider_probe;

import flint.java.nio.charset.spi.charsetprovider : CharsetProvider;

@safe:

private alias Cs = typeof(CharsetProvider.init.charsetForName(""));
private alias CsIter = typeof(CharsetProvider.init.charsets());

private final class SingleCharsetIterator : CsIter
{
    private Cs item;
    private bool done;

    this(Cs item) pure nothrow @nogc
    {
        this.item = item;
    }

    override bool hasNext() pure nothrow @nogc
    {
        return !done;
    }

    override Cs next() pure nothrow @nogc
    {
        done = true;
        return item;
    }

    override void remove() pure nothrow @nogc
    {
    }
}

private final class ProbeCharsetProvider : CharsetProvider
{
    this()
    {
        super();
    }

    override CsIter charsets()
    {
        return new SingleCharsetIterator(Cs.forName("UTF-8"));
    }

    override Cs charsetForName(string charsetName)
    {
        return charsetName.length > 0 ? Cs.forName("UTF-8") : Cs.init;
    }
}

int main(string[] args)
{
    CharsetProvider provider = new ProbeCharsetProvider();
    auto iter = provider.charsets();
    int count = 0;
    while (iter.hasNext())
    {
        if (iter.next().name().length > 0)
            ++count;
    }
    const found = provider.charsetForName(args.length > 1 ? args[1] : "UTF-8");
    return count + (found == Cs.init ? 0 : 1);
}
