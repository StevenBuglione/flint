module flint.term.contract_tests;

import flint.arena : Status;
import flint.term : Event, EventKind, KeyCode, Session;
import flint.term.internal : Decoder, escapeNanos, pasteBytes;

@safe:

private size_t feed(ref Decoder decoder, scope const(char)[] bytes, scope Event[] events, long now = 0)
{
    size_t received;
    size_t index;
    while (index < bytes.length)
    {
        auto step = decoder.feed(cast(ubyte) bytes[index], now);
        assert(step.consumed || step.ready);
        if (step.consumed)
            ++index;
        if (step.ready)
        {
            assert(received < events.length);
            events[received++] = step.value;
        }
    }
    return received;
}

private Event splitEvent(string bytes, size_t split)
{
    Decoder decoder;
    Event[1] events;
    const first = feed(decoder, bytes[0 .. split], events[]);
    const rest = feed(decoder, bytes[split .. $], events[first .. $], 1_000);
    assert(first + rest == 1);
    return events[0];
}

@("TERM-02 split UTF-8 scalar and CSI at every byte")
unittest
{
    enum scalar = "🦊";
    foreach (split; 0 .. scalar.length + 1)
    {
        const event = splitEvent(scalar, split);
        assert(event.kind == EventKind.key && event.key.code == KeyCode.character);
        assert(event.key.character == '🦊');
    }

    enum arrow = "\x1b[1;8A";
    foreach (split; 0 .. arrow.length + 1)
    {
        const event = splitEvent(arrow, split);
        assert(event.kind == EventKind.key && event.key.code == KeyCode.up);
        assert(event.key.shift && event.key.control && event.key.alt);
    }
}

@("TERM-02 malformed UTF-8 emits replacement and preserves the next byte")
unittest
{
    Decoder decoder;
    Event[6] events;
    assert(feed(decoder, "\xE2a\x80\xED\xA0\x80\xF4\x90\x80\x80", events[]) == 5);
    assert(events[0].key.character == '\uFFFD' && events[0].error.code == Status.invalidArgument);
    assert(events[1].key.character == 'a');
    assert(events[2].key.character == '\uFFFD' && events[3].key.character == '\uFFFD');
    assert(events[4].key.character == '\uFFFD' && decoder.invalidUtf8Count() == 4);
    assert(feed(decoder, "\xF0\x90", events[]) == 0);
    assert(decoder.endOfInput().value.key.character == '\uFFFD');
    assert(decoder.endOfInput().value.kind == EventKind.eof);
    assert(decoder.endOfInput().value.kind == EventKind.eof);
}

@("TERM-03 a standalone Escape expires once at 25 ms")
unittest
{
    Decoder decoder;
    assert(!decoder.feed(0x1B, 500).ready);
    assert(!decoder.expire(500 + escapeNanos - 1).ready);
    const event = decoder.expire(500 + escapeNanos);
    assert(event.ready && event.value.key.code == KeyCode.escape);
    assert(!decoder.expire(long.max).ready);
    assert(!decoder.feed(0x1B, long.max - 5).ready);
    assert(decoder.escapeDeadline() == long.max);
    assert(decoder.endOfInput().value.key.code == KeyCode.escape);
}

@("TERM-04 paste is owned, preserves control bytes, and recognizes only its exact marker")
unittest
{
    enum data = "a\x1b[31m\0\x1b[201X\x1b[20\x1b[\xFF";
    Event[2] events;
    foreach (split; 0 .. 7)
    {
        Decoder decoder;
        assert(feed(decoder, "\x1b[200~" ~ data, events[]) == 0);
        enum marker = "\x1b[201~";
        const first = feed(decoder, marker[0 .. split], events[]);
        const rest = feed(decoder, marker[split .. $], events[first .. $]);
        assert(first + rest == 1);
        const received = events[0];
        assert(received.kind == EventKind.paste && received.paste == data);
        assert(feed(decoder, "\x1b[200~new\x1b[201~x", events[]) == 2);
        assert(events[0].paste == "new" && events[1].key.character == 'x');
        assert(received.paste == data);
    }
}

@("TERM-04 paste capacity is inclusive and oversized tails stay data")
unittest
{
    Decoder decoder;
    Event[2] events;
    auto bytes = new char[pasteBytes];
    bytes[] = 'a';
    assert(feed(decoder, "\x1b[200~", events[]) == 0);
    assert(feed(decoder, bytes, events[]) == 0);
    assert(feed(decoder, "\x1b[201~", events[]) == 1);
    assert(events[0].paste.length == pasteBytes && events[0].error.code == Status.ok);

    assert(feed(decoder, "\x1b[200~", events[]) == 0);
    assert(feed(decoder, bytes, events[]) == 0);
    assert(feed(decoder, "\x1b[31mz\x1b[201~x", events[]) == 2);
    assert(events[0].kind == EventKind.paste && events[0].error.code == Status.resourceExhausted);
    assert(events[0].paste.length == 0 && events[1].key.character == 'x');

    assert(feed(decoder, "\x1b[200~unfinished", events[]) == 0);
    assert(decoder.endOfInput().value.error.code == Status.invalidArgument);
    assert(decoder.endOfInput().value.kind == EventKind.eof);
}

@("SGR mouse, control keys and unknown or overlong sequences")
unittest
{
    Decoder decoder;
    Event[8] events;
    enum input = "\x1b[<0;12;34M\x1b[<0;12;34m\x1b[<65;1;2M\x1b[<;1;2M\x1b[<>q" ~ "\x1bOP\x1b[24~\x1b[Z\x03\x1bx";
    assert(feed(decoder, input, events[]) == events.length);
    assert(events[0].kind == EventKind.mouse && events[0].mouse.pressed);
    assert(events[0].mouse.column == 12 && events[0].mouse.row == 34);
    assert(!events[1].mouse.pressed && events[2].mouse.button == 5);
    assert(events[3].key.code == KeyCode.functionKey && events[3].key.character == 1);
    assert(events[4].key.code == KeyCode.functionKey && events[4].key.character == 12);
    assert(events[5].key.code == KeyCode.tab && events[5].key.shift);
    assert(events[6].kind == EventKind.interrupt && events[7].key.alt && events[7].key.character == 'x');

    char[68] unknown;
    unknown[] = '9';
    unknown[0 .. 2] = "\x1b[";
    unknown[66] = 'A';
    unknown[67] = 'y';
    assert(feed(decoder, unknown[], events[]) == 1);
    assert(events[0].key.character == 'y');
}

@("move-only sessions reject use of an uninitialized handle")
unittest
{
    static assert(!__traits(compiles, {
            Session first;
            auto forbiddenCopy = first;
            first.close();
            forbiddenCopy.close();
        }));
    Session session;
    assert(session.close().code == Status.ok);
    assert(session.write("x").code == Status.cancelled);
    assert(session.size().error.code == Status.cancelled);
    assert(session.next(0).error.code == Status.cancelled);
}

@("TERM-02 escape sequences up to the 64-byte bound decode and longer ones are discarded")
unittest
{
    char[66] text;
    text[0 .. 2] = "\x1b[";
    Event[2] events;
    foreach (parameters; [3, 60, 61, 62, 63])
    {
        text[2 .. 2 + parameters - 3] = '0';
        text[2 + parameters - 3 .. 2 + parameters] = "1;2";
        text[2 + parameters] = 'A';
        Decoder decoder;
        const sequence = text[0 .. 3 + parameters];
        const received = feed(decoder, sequence ~ "z", events[]);
        if (sequence.length <= 64)
        {
            assert(received == 2 && events[0].key.code == KeyCode.up && events[0].key.shift);
            assert(events[1].key.character == 'z');
        }
        else
        {
            assert(received == 1 && events[0].key.character == 'z');
        }
    }
}
