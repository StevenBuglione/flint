module flint.term.contract_tests;

import flint.arena : Status;
import flint.term : ColorProfile, Event, EventKind, KeyCode, Session;
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

version (Posix)
{
    @("describe reports a pipe as a colorless non-terminal without touching terminal modes")
    unittest
    {
        import flint.term : Stream, describe;
        import core.sys.posix.unistd : close, dup, dup2, pipe;

        int[2] ends;
        assert(() @trusted { return pipe(ends); }() == 0);
        const saved = () @trusted { return dup(1); }();
        assert(saved >= 0);
        assert(() @trusted { return dup2(ends[1], 1); }() == 1);
        const info = describe(Stream.output);
        assert(() @trusted { return dup2(saved, 1); }() == 1);
        () @trusted { close(saved); close(ends[0]); close(ends[1]); }();
        assert(!info.terminal && info.size.columns == 0 && info.size.rows == 0);
        assert(info.colors == ColorProfile.none);
    }

    /// A pseudo-terminal whose slave temporarily replaces stderr; restored and closed on destruction.
    private struct PseudoTerminal
    {
        int master = -1;
        int slave = -1;
        int saved = -1;

        @disable this(this);

        static PseudoTerminal open(ushort columns, ushort rows) @trusted
        {
            import core.sys.posix.fcntl : O_NOCTTY, O_RDWR, fcntlOpen = open;
            import core.sys.posix.stdlib : grantpt, posix_openpt, ptsname, unlockpt;
            import core.sys.posix.sys.ioctl : TIOCSWINSZ, ioctl, winsize;
            import core.sys.posix.unistd : dup, dup2;

            PseudoTerminal terminal;
            terminal.master = posix_openpt(O_RDWR | O_NOCTTY);
            assert(terminal.master >= 0 && grantpt(terminal.master) == 0 && unlockpt(terminal.master) == 0);
            terminal.slave = fcntlOpen(ptsname(terminal.master), O_RDWR | O_NOCTTY);
            assert(terminal.slave >= 0);
            winsize window;
            window.ws_col = columns;
            window.ws_row = rows;
            assert(ioctl(terminal.slave, TIOCSWINSZ, &window) == 0);
            terminal.saved = dup(2);
            assert(terminal.saved >= 0 && dup2(terminal.slave, 2) == 2);
            return terminal;
        }

        ~this() @trusted
        {
            import core.sys.posix.unistd : close, dup2;

            if (saved >= 0)
            {
                dup2(saved, 2);
                close(saved);
            }
            if (slave >= 0)
                close(slave);
            if (master >= 0)
                close(master);
        }
    }
}

/// Set or unset environment variables, restoring them on destruction.
private struct ScopedEnvironment
{
    string[string] previous;
    string[] names;

    @disable this(this);

    void set(string name, string value)
    {
        import std.process : environment;

        remember(name);
        if (value is null)
            environment.remove(name);
        else
            environment[name] = value;
    }

    private void remember(string name)
    {
        import std.process : environment;

        foreach (known; names)
        {
            if (known == name)
                return;
        }
        names ~= name;
        const value = environment.get(name, null);
        if (value !is null)
            previous[name] = value;
    }

    ~this()
    {
        import std.process : environment;

        foreach (name; names)
        {
            if (auto value = name in previous)
                environment[name] = *value;
            else
                environment.remove(name);
        }
    }
}

version (Posix)
{
    @("describe reads a pseudo-terminal's window size and honours TERM, COLORTERM and NO_COLOR")
    unittest
    {
        import flint.term : Stream, describe;

        ScopedEnvironment variables;
        const terminal = PseudoTerminal.open(97, 31);
        assert(terminal.slave >= 0 && terminal.saved >= 0);
        variables.set("TERM", "xterm-256color");
        variables.set("COLORTERM", null);
        variables.set("NO_COLOR", null);
        auto info = describe(Stream.error);
        assert(info.terminal && info.size.columns == 97 && info.size.rows == 31);
        assert(info.colors == ColorProfile.ansi256);
        variables.set("COLORTERM", "truecolor");
        assert(describe(Stream.error).colors == ColorProfile.trueColor);
        variables.set("NO_COLOR", "1");
        info = describe(Stream.error);
        assert(info.terminal && info.colors == ColorProfile.none);
        variables.set("NO_COLOR", null);
        variables.set("TERM", "dumb");
        assert(describe(Stream.error).colors == ColorProfile.none);
    }
}
