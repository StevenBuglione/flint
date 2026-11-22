/// Terminal input, raw-mode guards and output capabilities.
module flint.term;

import flint.arena : Error, Result, Status;
public import flint.term.events : ColorProfile, Event, EventKind, KeyCode, KeyEvent, MouseEvent, Options, Size;

@safe:

// The native terminal session is native/linux.c on Linux and macOS, and flint.term.sys.windows_console on
// Windows, both behind the ABI in flint.term.sys.linux_abi.
version (linux)
    version = FlintTermNative;
else version (OSX)
    version = FlintTermNative;
else version (Windows)
    version = FlintTermNative;

version (FlintTermNative) import flint.term.sys.linux_session : LinuxSession;

/// Own a terminal session. Move only while no other caller is borrowing it.
struct Session
{
    @disable this(this);

    version (FlintTermNative)
    {
        private LinuxSession state;

        private this(LinuxSession state)
        {
            this.state = state;
        }

        ~this() scope nothrow
        {
            if (state !is null)
                state.dispose();
        }
    }

    /// Open a session over the current standard input and output.
    static Result!Session open(Options options = Options.init)
    {
        version (FlintTermNative)
        {
            auto result = LinuxSession.open(options);
            if (!result.ok())
                return Result!Session(Session.init, result.error);
            return Result!Session(Session(result.value));
        }
        else
        {
            return Result!Session(Session.init, unsupported());
        }
    }

    /// Read one event. A negative timeout waits indefinitely and zero polls.
    Result!Event next(long timeoutNanos)
    {
        version (FlintTermNative)
            return state is null ? Result!Event(Event.init, inactive()) : state.next(timeoutNanos);
        else
            return Result!Event(Event.init, unsupported());
    }

    /// Write trusted application formatting to the output stream.
    Error write(scope const(char)[] text)
    {
        version (FlintTermNative)
            return state is null ? inactive() : state.write(text);
        else
            return unsupported();
    }

    /// Query current terminal dimensions.
    Result!Size size() const
    {
        version (FlintTermNative)
            return state is null ? Result!Size(Size.init, inactive()) : state.size();
        else
            return Result!Size(Size.init, unsupported());
    }

    /// Report the color capability recorded at open.
    ColorProfile colors() const
    {
        version (FlintTermNative)
            return state is null ? ColorProfile.none : state.colors();
        else
            return ColorProfile.none;
    }

    /// Wake blocked callers and restore owned modes. Repeated calls are safe.
    Error close()
    {
        version (FlintTermNative)
            return state is null ? Error.init : state.close();
        else
            return Error.init;
    }
}

/// A standard output stream a line-oriented tool writes to.
enum Stream : ubyte
{
    output,
    error
}

/// Write text to standard output or standard error and flush it: a line-oriented tool's results, messages and
/// errors, from `@safe` code and without a terminal session. Output keeps its order with std.stdio's.
Error writeStream(Stream stream, scope const(char)[] text) nothrow @nogc
{
    import flint.term.sys.output : writeStandard;

    if (writeStandard(stream == Stream.error, text))
        return Error.init;
    return Error(Status.ioError, stream == Stream.error
            ? "could not write to standard error" : "could not write to standard output");
}

/// Capabilities of a standard output stream, read without owning the terminal.
struct StreamInfo
{
    /// The stream is connected to a terminal.
    bool terminal;
    /// Colors the terminal accepts; none when the stream is not a terminal or NO_COLOR is set.
    ColorProfile colors;
    /// Window size, or zero columns and rows when the terminal does not report one.
    Size size;
}

/// Describe stdout or stderr for line-oriented output. Unlike `Session.open`, this never changes
/// terminal modes, enters the alternate screen or reads input.
StreamInfo describe(Stream stream)
{
    StreamInfo info;
    version (FlintTermNative)
    {
        import flint.term.sys.linux_session : environmentColors;
        import flint.term.sys.output : probeStream;

        info.terminal = probeStream(stream == Stream.output ? 1 : 2, info.size);
        if (info.terminal)
            info.colors = environmentColors();
    }
    return info;
}

private Error unsupported() pure nothrow @nogc
{
    return Error(Status.unsupported, "terminal sessions are unavailable on this platform");
}

private Error inactive() pure nothrow @nogc
{
    return Error(Status.cancelled, "terminal session is inactive");
}
