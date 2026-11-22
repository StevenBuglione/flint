/// Non-owning capability probe of a standard output stream.
module flint.term.sys.output;

@safe:

version (linux)
{
    import flint.term.events : Size;

    /// Whether descriptor 1 or 2 is a terminal, and its window size when it reports one.
    package(flint.term) bool probeStream(int descriptor, out Size size) nothrow @nogc
    {
        if (descriptor != 1 && descriptor != 2)
            return false;
        if (!terminalDescriptor(descriptor))
            return false;
        windowSize(descriptor, size);
        return true;
    }

    // SAFETY: isatty only inspects the descriptor number, which is restricted to the process's own stdout or stderr;
    // no memory is passed.
    private bool terminalDescriptor(int descriptor) @trusted nothrow @nogc
    {
        import core.sys.posix.unistd : isatty;

        return isatty(descriptor) == 1;
    }

    // SAFETY: TIOCGWINSZ writes exactly one winsize into the local struct, whose address is valid for the call;
    // the fields are copied out only after a successful return.
    private void windowSize(int descriptor, out Size size) @trusted nothrow @nogc
    {
        import core.sys.posix.sys.ioctl : TIOCGWINSZ, ioctl, winsize;

        winsize window;
        if (ioctl(descriptor, TIOCGWINSZ, &window) == 0)
            size = Size(window.ws_col, window.ws_row);
    }
}
