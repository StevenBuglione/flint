module flint.term.fuzz_corpus;

import flint.arena : Status;
import flint.term : Event, EventKind, KeyCode;
import flint.term.internal : Decoder, escapeNanos, pasteBytes;

@safe:

private void check(bool passes)
{
    if (!passes)
        assert(0, "terminal corpus invariant failed");
}

private void checkEvent(scope ref const Event event)
{
    if (event.kind == EventKind.key && event.key.code == KeyCode.character)
    {
        const scalar = event.key.character;
        check(scalar <= 0x10_FFFF && (scalar < 0xD800 || scalar > 0xDFFF));
    }
    if (event.kind == EventKind.paste)
        check(event.paste.length <= pasteBytes);
    if (event.error.code == Status.resourceExhausted)
        check(event.kind == EventKind.paste && event.paste.length == 0);
}

private size_t drive(ref Decoder decoder, scope const(ubyte)[] input, long now)
{
    size_t index;
    size_t steps;
    while (index < input.length)
    {
        const token = decoder.feed(input[index], now);
        check(++steps <= input.length * 2);
        check(token.consumed || token.ready);
        if (token.ready)
            checkEvent(token.value);
        if (token.consumed)
            ++index;
    }
    return steps;
}

private uint nextByte(ref uint root) pure nothrow @nogc
{
    root ^= root << 13;
    root ^= root >> 17;
    root ^= root << 5;
    return root;
}

/// Exercise a bounded random input with a deterministic seed and chunk pattern.
ulong exerciseRandom(scope ubyte[] input, ref uint seed, long timeBias = 0)
{
    // Advance the seed even for an empty sample so it cannot trap replay at
    // the same zero length indefinitely.
    timeBias += nextByte(seed) % (escapeNanos + 1);
    foreach (ref byteValue; input)
        byteValue = cast(ubyte) nextByte(seed);

    Decoder decoder;
    ulong steps;
    while (input.length != 0)
    {
        size_t chunk = 1 + nextByte(seed) % 16;
        if (chunk > input.length)
            chunk = input.length;
        timeBias += nextByte(seed) % (escapeNanos + 1);
        const expiration = decoder.expire(timeBias);
        if (expiration.ready)
            checkEvent(expiration.value);
        steps += drive(decoder, input[0 .. chunk], timeBias);
        input = input[chunk .. $];
    }
    const first = decoder.endOfInput();
    check(first.ready);
    checkEvent(first.value);
    const second = decoder.endOfInput();
    check(second.ready && second.value.kind == EventKind.eof);
    return steps;
}

/// Cover every short length and exact boundary paste lengths.
void exerciseBoundaries(ref uint seed)
{
    ubyte[257] data;
    foreach (length; 0 .. data.length)
    {
        const steps = exerciseRandom(data[0 .. length], seed);
        check(steps >= length && steps <= 2 * length);
    }

    foreach (length; [1023, 1024, 1025, pasteBytes - 1, pasteBytes, pasteBytes + 1])
    {
        Decoder decoder;
        check(drive(decoder, cast(const(ubyte)[]) "\x1b[200~", 0) == 6);
        auto payload = new ubyte[length];
        payload[] = 'x';
        check(drive(decoder, payload, 0) == payload.length);
        check(drive(decoder, cast(const(ubyte)[]) "\x1b[201~", 0) == 6);
        check(decoder.endOfInput().value.kind == EventKind.eof);
    }
}

@("the deterministic terminal decoder seed corpus is bounded and makes progress")
unittest
{
    uint seed = 0xF21A_B08D;
    exerciseBoundaries(seed);
    seed ^= 0x9E37_79B9;
    ubyte[16] sample;
    assert(exerciseRandom(sample[], seed) >= sample.length);
}
