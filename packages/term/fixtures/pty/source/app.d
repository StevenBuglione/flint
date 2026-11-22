module app;

import core.stdc.signal : SIGINT, signal;
import core.thread.osthread : Thread;
import core.time : MonoTime, dur;
import flint.arena : Status;
import flint.term : ColorProfile, Event, EventKind, KeyCode, Options, Session;
import std.algorithm.mutation : move;
import std.format : format;
import std.stdio : stderr;

@safe:

private class Expected : Exception
{
    this()
    {
        super("fixture exception");
    }
}

private void verify(bool condition)
{
    if (!condition)
        throw new Exception("terminal fixture invariant failed");
}

// SAFETY: stderr is owned by the fixture process and outlives this synchronous write.
private void note(string line) @trusted
{
    stderr.writeln(line);
    stderr.flush();
}

private struct Waiting
{
    Session terminal;
    Status result;

    void read()
    {
        result = terminal.next(-1).error.code;
    }
}

// SAFETY: The fixture thread captures a rooted heap owner and is joined
// before that owner is destroyed.
private void launch(Thread worker) @trusted
{
    worker.start();
}

// SAFETY: Only the fixture's main thread joins its one owned worker.
private void join(Thread worker) @trusted
{
    worker.join();
}

// SAFETY: This finite-lived subprocess uses a C callback with no captures and
// no retained D data.
private void claimInterrupt() @trusted
{
    signal(SIGINT, &existingHandler);
}

private extern (C) void existingHandler(int) nothrow @nogc
{
}

private void cancelBlocked()
{
    auto created = Session.open(Options(true, true, true, true));
    verify(created.ok());
    auto state = new Waiting;
    move(created.value, state.terminal);
    scope (exit)
        destroy(state.terminal);

    auto worker = new Thread(() { state.read(); });
    launch(worker);
    Thread.sleep(dur!"msecs"(50));
    verify(state.terminal.close().code == Status.ok);
    join(worker);
    verify(state.result == Status.cancelled);
    verify(state.terminal.close().code == Status.ok);
    note("CANCELLED");
}

private Event receive(ref Session terminal)
{
    auto reply = terminal.next(3_000_000_000);
    verify(reply.ok());
    return reply.value;
}

private void readEvents(ref Session terminal)
{
    auto current = receive(terminal);
    verify(current.key.code == KeyCode.character && current.key.character == '🦊');
    note("UNICODE");
    current = receive(terminal);
    verify(current.key.code == KeyCode.up && current.key.shift && current.key.control);
    note("CSI");
    current = receive(terminal);
    verify(current.kind == EventKind.paste && current.paste == "abc\x1b[2J\0\xFF");
    note("PASTE");
    current = receive(terminal);
    verify(current.kind == EventKind.interrupt);
    note("CTRL_C");
}

private void waitEscape(ref Session terminal)
{
    const begin = MonoTime.currTime;
    const result = receive(terminal);
    const nanos = (MonoTime.currTime - begin).total!"nsecs";
    verify(result.key.code == KeyCode.escape && nanos >= 25_000_000 && nanos < 2_000_000_000);
    note(format!"ESCAPE %s"(nanos));
}

private void expectResize(ref Session terminal)
{
    Thread.sleep(dur!"msecs"(200));
    const result = receive(terminal);
    verify(result.kind == EventKind.resize && result.size.columns == 113 && result.size.rows == 47);
    verify(terminal.next(20_000_000).error.code == Status.timedOut);
    note("RESIZED_ONCE");
}

private void measureIdle(ref Session terminal)
{
    const result = terminal.next(10_000_000_000);
    verify(result.error.code == Status.timedOut);
    note("IDLE_TIMEOUT");
}

private void useTerminal(string mode)
{
    auto created = Session.open(Options(true, true, true, true));
    verify(created.ok());
    verify(created.value.colors() == ColorProfile.trueColor);
    const dimensions = created.value.size();
    verify(dimensions.ok() && dimensions.value.columns == 80 && dimensions.value.rows == 24);
    // No other owner may replace this terminal's raw and signal state.
    auto second = Session.open();
    verify(second.error.code == Status.conflict);
    note("READY");

    switch (mode)
    {
    case "normal":
        verify(receive(created.value).key.character == 'x');
        verify(created.value.close().code == Status.ok);
        verify(created.value.close().code == Status.ok);
        break;
    case "exception":
        verify(receive(created.value).key.character == 'x');
        throw new Expected;
    case "events":
        readEvents(created.value);
        break;
    case "escape":
        waitEscape(created.value);
        break;
    case "resize":
        expectResize(created.value);
        break;
    case "signal":
        verify(receive(created.value).kind == EventKind.interrupt);
        note("SIGNAL_INTERRUPT");
        break;
    case "idle":
        measureIdle(created.value);
        break;
    case "terminate":
        // The driver sends SIGTERM or SIGHUP. The process must still terminate by that signal.
        receive(created.value);
        throw new Exception("termination signal did not terminate the fixture");
    default:
        throw new Exception("unknown PTY fixture mode");
    }
}

private void useStreams(bool broken)
{
    auto raw = Session.open();
    verify(raw.error.code == Status.unsupported);

    auto plain = Session.open(Options(false));
    verify(plain.ok());
    verify(plain.value.colors() == ColorProfile.none);
    verify(plain.value.size().error.code == Status.unsupported);
    verify(receive(plain.value).kind == EventKind.eof);
    verify(receive(plain.value).kind == EventKind.eof);
    verify(plain.value.write("ordinary output\n").code == (broken ? Status.ioError : Status.ok));
}

private void useTerminalInputOnly()
{
    // TERM-06: a terminal on stdin with stdout redirected cannot enter raw mode.
    auto raw = Session.open(Options(true, true, true, true));
    verify(raw.error.code == Status.unsupported);
    auto plain = Session.open(Options(false));
    verify(plain.ok());
    verify(plain.value.colors() == ColorProfile.none);
    verify(plain.value.write("ordinary output\n").code == Status.ok);
    verify(plain.value.close().code == Status.ok);
    verify(plain.value.close().code == Status.ok);
    verify(plain.value.write("late").code == Status.cancelled);
}

void main(string[] args)
{
    verify(args.length == 2);
    switch (args[1])
    {
    case "cancel":
        cancelBlocked();
        break;
    case "streams":
        useStreams(false);
        break;
    case "broken":
        useStreams(true);
        break;
    case "piped-output":
        useTerminalInputOnly();
        break;
    case "conflict":
        claimInterrupt();
        auto result = Session.open();
        verify(result.error.code == Status.conflict);
        note("CONFLICT");
        break;
    default:
        try
        {
            useTerminal(args[1]);
        }
        catch (Expected)
        {
            verify(args[1] == "exception");
            note("CAUGHT");
        }
        break;
    }
}
