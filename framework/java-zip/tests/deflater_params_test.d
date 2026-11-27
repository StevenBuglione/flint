// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module deflater_params_test;

import flint.java.lang : IllegalArgumentException;
import flint.java.util.zip : Deflater, Inflater;

@safe:

private const suffix = cast(const(byte)[]) "tail bytes after change";
private const changed = cast(const(byte)[]) x"
    789c72741c5850929899a3905459925aac90985692
    5aa4909c9198979e0a080000ffff84fb292a
";
private const afterReset = cast(const(byte)[]) x"78012b49cccc5148aa2c492d56484c2b492d5248ce48cc4b4f0500681608aa";

@("deflater keeps a pending level and strategy change across a full output buffer")
unittest
{
    auto encoder = new Deflater();
    auto decoder = new Inflater();
    scope (exit)
    {
        encoder.end();
        decoder.end();
    }

    auto prefix = new byte[128];
    prefix[] = cast(byte) 'A';
    byte[256] output;
    encoder.setLevel(Deflater.DEFAULT_COMPRESSION);
    encoder.setStrategy(Deflater.DEFAULT_STRATEGY);
    encoder.setInput(prefix);
    size_t written = encoder.deflate(output[]);
    assert(written == 2 && encoder.needsInput() && encoder.getBytesRead() == prefix.length);
    encoder.setLevel(Deflater.NO_COMPRESSION);
    encoder.setStrategy(Deflater.HUFFMAN_ONLY);
    encoder.setInput(suffix);
    encoder.finish();
    assert(encoder.deflate(null) == 0);
    assert(encoder.getBytesRead() == prefix.length && !encoder.finished());

    int calls;
    int stalls;
    int firstInputCall = -1;
    while (!encoder.finished())
    {
        assert(++calls < output.length);
        const count = encoder.deflate(output[written .. written + 1]);
        if (count == 0)
            ++stalls;
        written += count;
        if (firstInputCall == -1 && encoder.getBytesRead() > prefix.length)
            firstInputCall = calls;
    }
    assert(calls == 38 && stalls == 1 && firstInputCall == 1);
    assert(encoder.needsInput() && encoder.getBytesRead() == prefix.length + suffix.length);
    assert(encoder.getBytesWritten() == written && output[0 .. written] == changed);

    decoder.setInput(changed);
    byte[256] restored;
    const count = decoder.inflate(restored[]);
    assert(decoder.finished() && count == prefix.length + suffix.length);
    assert(restored[0 .. prefix.length] == prefix);
    assert(restored[prefix.length .. count] == suffix);
}

@("deflater preserves a pending parameter change through reset and rejected settings")
unittest
{
    auto encoder = new Deflater(Deflater.NO_COMPRESSION);
    scope (exit)
        encoder.end();
    encoder.setInput(suffix);
    encoder.finish();
    byte[64] output;
    assert(encoder.deflate(output[]) > 0 && encoder.finished());

    encoder.setLevel(Deflater.BEST_SPEED);
    encoder.setStrategy(Deflater.FILTERED);
    bool badLevel;
    try
        encoder.setLevel(-2);
    catch (IllegalArgumentException error)
        badLevel = error.msg == "invalid compression level";
    bool badStrategy;
    try
        encoder.setStrategy(3);
    catch (IllegalArgumentException error)
        badStrategy = error.msg is null;
    assert(badLevel && badStrategy);

    encoder.reset();
    encoder.setInput(suffix);
    encoder.finish();
    assert(encoder.deflate(output[]) == 0 && !encoder.finished());
    assert(encoder.getBytesRead() == 0 && encoder.getBytesWritten() == 0);
    const count = encoder.deflate(output[]);
    assert(encoder.finished() && encoder.getBytesRead() == suffix.length);
    assert(encoder.getBytesWritten() == count && output[0 .. count] == afterReset);
}

@("deflater credits output written during a pending parameter retry")
unittest
{
    auto encoder = new Deflater();
    scope (exit)
        encoder.end();
    auto prefix = new byte[128];
    prefix[] = cast(byte) 'A';
    byte[64] output;

    encoder.setInput(prefix);
    assert(encoder.deflate(output[0 .. 1]) == 1);
    assert(encoder.getBytesRead() == 0 && encoder.getBytesWritten() == 1);
    encoder.setLevel(Deflater.NO_COMPRESSION);
    encoder.finish();

    assert(encoder.deflate(null) == 0);
    assert(encoder.deflate(output[1 .. 2]) == 1);
    assert(encoder.getBytesRead() == 0 && encoder.getBytesWritten() == 2);
    assert(encoder.deflate(output[2 .. $]) == 5);
    assert(encoder.getBytesRead() == prefix.length && encoder.getBytesWritten() == 7);
    assert(!encoder.finished());
    assert(encoder.deflate(output[7 .. $]) == 9 && encoder.finished());
    assert(encoder.getBytesWritten() == 16);
}
