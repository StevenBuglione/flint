/// Terminal input, raw-mode guards and output capabilities.
module flint.term;

import flint.arena : Error, Result, Status;
public import flint.term.events : ColorProfile, Event, EventKind, KeyCode, KeyEvent, MouseEvent, Options, Size;

@safe:

version (linux) import flint.term.sys.linux_session : LinuxSession;

/// Own a terminal session. Move only while no other caller is borrowing it.
struct Session
{
    @disable this(this);

    version (linux)
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
        version (linux)
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
        version (linux)
            return state is null ? Result!Event(Event.init, inactive()) : state.next(timeoutNanos);
        else
            return Result!Event(Event.init, unsupported());
    }

    /// Write trusted application formatting to the output stream.
    Error write(scope const(char)[] text)
    {
        version (linux)
            return state is null ? inactive() : state.write(text);
        else
            return unsupported();
    }

    /// Query current terminal dimensions.
    Result!Size size() const
    {
        version (linux)
            return state is null ? Result!Size(Size.init, inactive()) : state.size();
        else
            return Result!Size(Size.init, unsupported());
    }

    /// Report the color capability recorded at open.
    ColorProfile colors() const
    {
        version (linux)
            return state is null ? ColorProfile.none : state.colors();
        else
            return ColorProfile.none;
    }

    /// Wake blocked callers and restore owned modes. Repeated calls are safe.
    Error close()
    {
        version (linux)
            return state is null ? Error.init : state.close();
        else
            return Error.init;
    }
}

private Error unsupported() pure nothrow @nogc
{
    return Error(Status.unsupported, "terminal sessions are unavailable on this platform");
}

private Error inactive() pure nothrow @nogc
{
    return Error(Status.cancelled, "terminal session is inactive");
}
