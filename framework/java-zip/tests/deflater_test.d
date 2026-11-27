// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module deflater_test;

import flint.java.lang : IllegalArgumentException, NullPointerException;
import flint.java.util.zip : Deflater, Inflater;

@safe:

private const payload = cast(const(byte)[]) "flint deflate deflate deflate lifecycle";
private const wrapped = cast(const(byte)[]) x"789c4bcbc9cc2b5148494dcb492c49c5a07332d352932b9373520126540ecd";
private const raw = cast(const(byte)[]) x"4bcbc9cc2b5148494dcb492c49c5a07332d352932b93735201";
private const withDictionary = cast(const(byte)[]) x"78bb734d09694b431547a37332d352932b9373520126540ecd";

@("deflater finishes in single-byte output chunks and resets for replay")
unittest
{
    auto encoder = new Deflater();
    scope (exit)
        encoder.end();
    byte[64] output;
    foreach (round; 0 .. 2)
    {
        encoder.setInput(payload);
        assert(encoder.deflate(null) == 0 && encoder.getBytesRead() == 0);
        encoder.finish();
        size_t written;
        foreach (attempt; 0 .. output.length)
        {
            written += encoder.deflate(output[written .. written + 1]);
            if (encoder.finished())
                break;
        }
        assert(encoder.finished() && encoder.needsInput());
        assert(encoder.getBytesRead() == payload.length);
        assert(encoder.getBytesWritten() == written);
        assert(output[0 .. written] == wrapped);
        encoder.reset();
        assert(!encoder.finished() && encoder.needsInput());
        assert(encoder.getBytesRead() == 0 && encoder.getBytesWritten() == 0);
    }
}

@("raw and dictionary streams match pinned Temurin without crediting dictionary input")
unittest
{
    auto rawEncoder = new Deflater(Deflater.DEFAULT_COMPRESSION, true);
    scope (exit)
        rawEncoder.end();
    rawEncoder.setInput(payload);
    rawEncoder.finish();
    byte[64] output;
    const rawCount = rawEncoder.deflate(output[]);
    assert(rawEncoder.finished() && output[0 .. rawCount] == raw);

    auto encoder = new Deflater(Deflater.DEFAULT_COMPRESSION);
    scope (exit)
        encoder.end();
    encoder.setDictionary(cast(const(byte)[]) "flint deflate dictionary");
    assert(encoder.getBytesRead() == 0 && encoder.getAdler() == 0x734d0969);
    encoder.setInput(payload);
    encoder.finish();
    const count = encoder.deflate(output[]);
    assert(encoder.finished() && encoder.getBytesRead() == payload.length);
    assert(output[0 .. count] == withDictionary);
}

@("deflater ends an unfinished stream and rejects a closed read or invalid level")
unittest
{
    auto encoder = new Deflater();
    scope (exit)
        encoder.end();
    encoder.setInput(payload);
    byte[8] output;
    assert(encoder.deflate(output[]) == 2);
    assert(!encoder.finished());
    encoder.end();
    encoder.end();

    bool closed;
    try
        encoder.getBytesRead();
    catch (NullPointerException error)
        closed = error.msg == "Deflater has been closed";
    assert(closed);

    bool invalidLevel;
    try
        new Deflater(10);
    catch (IllegalArgumentException error)
        invalidLevel = error.msg is null;
    assert(invalidLevel);
}

@("deflater preserves pending input across an overlapping output write")
unittest
{
    auto encoder = new Deflater(Deflater.NO_COMPRESSION);
    auto inflater = new Inflater();
    scope (exit)
    {
        encoder.end();
        inflater.end();
    }
    auto buffer = new byte[128];
    buffer[0 .. payload.length] = payload;
    encoder.setInput(buffer[0 .. payload.length]);
    encoder.finish();
    // The header and stored block would overwrite unread input without staging.
    const count = encoder.deflate(buffer[]);
    assert(encoder.finished() && count > payload.length);
    inflater.setInput(buffer[0 .. count]);
    byte[64] output;
    const decoded = inflater.inflate(output[]);
    assert(inflater.finished() && output[0 .. decoded] == payload);
}
