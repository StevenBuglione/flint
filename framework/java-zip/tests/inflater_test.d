// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module inflater_test;

import flint.java.lang : IllegalArgumentException, NullPointerException;
import flint.java.util.zip : DataFormatException, Inflater;

@safe:

private const payload = cast(const(byte)[]) "flint deflate deflate deflate lifecycle";
private const wrapped = cast(const(byte)[]) x"789c4bcbc9cc2b5148494dcb492c49c5a07332d352932b9373520126540ecd";
private const raw = cast(const(byte)[]) x"4bcbc9cc2b5148494dcb492c49c5a07332d352932b9373520100";
private const withDictionary = cast(const(byte)[]) x"78bb734d09694b431547a37332d352932b9373520126540ecd";

@("inflater updates counters, preserves trailing input and resets native state")
unittest
{
    auto inflater = new Inflater();
    scope (exit)
        inflater.end();
    byte[64] output;
    auto input = wrapped.dup ~ cast(byte) 17;
    foreach (round; 0 .. 2)
    {
        input[0] = 0x12;
        inflater.setInput(input);
        input[0] = wrapped[0];
        assert(inflater.inflate(null) == 0);
        assert(inflater.inflate(output[]) == payload.length);
        assert(output[0 .. payload.length] == payload);
        assert(inflater.finished() && !inflater.needsInput());
        assert(inflater.getRemaining() == 1);
        assert(inflater.getBytesRead() == wrapped.length);
        assert(inflater.getBytesWritten() == payload.length);
        assert(inflater.getAdler() == 0x26540ecd);
        inflater.reset();
        assert(!inflater.finished() && inflater.needsInput());
        assert(inflater.getBytesRead() == 0 && inflater.getBytesWritten() == 0);
    }
    inflater.setInput(null);
    assert(inflater.needsInput());
    assert(inflater.inflate([]) == 0);
}

@("raw inflater and dictionary retries match Temurin")
unittest
{
    auto unwrapped = new Inflater(true);
    scope (exit)
        unwrapped.end();
    byte[64] output;
    unwrapped.setInput(raw);
    assert(unwrapped.inflate(output[]) == payload.length);
    assert(unwrapped.finished() && output[0 .. payload.length] == payload);

    auto inflater = new Inflater();
    scope (exit)
        inflater.end();
    inflater.setInput(withDictionary);
    assert(inflater.inflate(output[]) == 0);
    assert(inflater.needsDictionary() && inflater.getBytesRead() == 6);
    assert(inflater.getAdler() == 0x734d0969);
    const byte[1] incorrect;
    bool rejected;
    try
        inflater.setDictionary(incorrect[]);
    catch (IllegalArgumentException error)
        rejected = true;
    assert(rejected && inflater.needsDictionary() && inflater.getBytesRead() == 6);
    inflater.setDictionary(cast(const(byte)[]) "flint deflate dictionary");
    assert(!inflater.needsDictionary());
    assert(inflater.inflate(output[]) == payload.length);
    assert(inflater.finished() && inflater.getRemaining() == 0);
    assert(inflater.getBytesRead() == withDictionary.length);
    assert(output[0 .. payload.length] == payload);
}

@("data format errors publish consumed input and closed streams reject reset")
unittest
{
    auto inflater = new Inflater();
    scope (exit)
        inflater.end();
    byte[4] output;
    inflater.setInput(cast(const(byte)[]) x"1234");
    bool malformed;
    try
        inflater.inflate(output[]);
    catch (DataFormatException error)
        malformed = error.msg == "incorrect header check";
    assert(malformed && inflater.getBytesRead() == 2 && inflater.getBytesWritten() == 0);
    assert(inflater.getRemaining() == 0);
    inflater.end();
    inflater.end();
    bool closed;
    try
        inflater.reset();
    catch (NullPointerException error)
        closed = error.msg == "Inflater has been closed";
    assert(closed);
}

@("malformed trailer credits output produced before checksum failure")
unittest
{
    auto inflater = new Inflater();
    scope (exit)
        inflater.end();
    auto corrupt = wrapped.dup;
    corrupt[$ - 1] ^= 1;
    inflater.setInput(corrupt);
    byte[64] output;
    bool failed;
    try
        inflater.inflate(output[]);
    catch (DataFormatException error)
        failed = error.msg == "incorrect data check";
    assert(failed && inflater.getBytesRead() == wrapped.length);
    assert(inflater.getBytesWritten() == payload.length);
    assert(output[0 .. payload.length] == payload);
}

@("stored deflate data can be decoded into the same array")
unittest
{
    auto inflater = new Inflater();
    scope (exit)
        inflater.end();
    const stored = x"7801012700d8ff666c696e74206465666c617465206465666c"
        ~ x"617465206465666c617465206c6966656379636c6526540ecd";
    auto sharedBytes = (cast(const(byte)[]) stored).dup;
    inflater.setInput(sharedBytes);
    assert(inflater.inflate(sharedBytes) == payload.length);
    assert(sharedBytes[0 .. payload.length] == payload);
    assert(inflater.finished());
}

@("data format exceptions treat any empty detail as absent")
unittest
{
    string detail = "invalid compressed data";
    auto empty = detail[0 .. 0];
    assert(empty !is null);
    assert((new DataFormatException(empty)).msg is null);
    assert((new DataFormatException(null)).msg is null);
    assert((new DataFormatException()).msg is null);
    assert((new DataFormatException(detail)).msg == detail);
}
