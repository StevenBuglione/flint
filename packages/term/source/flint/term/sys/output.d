/// Non-owning capability probe of a standard output stream, and line-oriented writes to it.
module flint.term.sys.output;

@safe:

/// Write all of `text` to standard output, or standard error when `error`, through the C runtime's stream (the one
/// std.stdio also writes through, so the order of output is kept), then flush it. False when either fails.
// SAFETY: `text` is a live slice that fwrite only reads, for exactly `text.length` bytes, during the call; stdout
// and stderr are the C runtime's own streams, valid for the life of the process, and are never stored.
package(flint.term) bool writeStandard(bool error, scope const(char)[] text) @trusted nothrow @nogc
{
    import core.stdc.stdio : FILE, fflush, fwrite, stderr, stdout;

    FILE* stream = error ? stderr : stdout;
    const written = text.length == 0 ? 0 : fwrite(text.ptr, 1, text.length, stream);
    return written == text.length && fflush(stream) == 0;
}

// The native terminal session (native/linux.c) is built for Linux and macOS.
version (linux)
    version = FlintTermNative;
else version (OSX)
    version = FlintTermNative;

version (Windows)
{
    import flint.term.events : Size;

    /// Whether standard output (1) or standard error (2) is a console, and its window size. A console counts as
    /// a terminal only while it interprets virtual-terminal sequences, which this probe never switches on.
    // SAFETY: GetStdHandle borrows the process's own handle; the mode and buffer queries write only locals.
    package(flint.term) bool probeStream(int descriptor, out Size size) @trusted nothrow @nogc
    {
        import core.sys.windows.wincon : CONSOLE_SCREEN_BUFFER_INFO, GetConsoleMode, GetConsoleScreenBufferInfo;
        import core.sys.windows.winbase : GetStdHandle, STD_ERROR_HANDLE, STD_OUTPUT_HANDLE;

        enum uint virtualTerminalProcessing = 0x0004;
        if (descriptor != 1 && descriptor != 2)
            return false;
        auto handle = GetStdHandle(descriptor == 1 ? STD_OUTPUT_HANDLE : STD_ERROR_HANDLE);
        uint mode;
        if (handle is null || !GetConsoleMode(handle, &mode) || (mode & virtualTerminalProcessing) == 0)
            return false;
        CONSOLE_SCREEN_BUFFER_INFO information;
        if (GetConsoleScreenBufferInfo(handle, &information))
            size = Size(information.srWindow.Right - information.srWindow.Left + 1,
                    information.srWindow.Bottom - information.srWindow.Top + 1);
        return true;
    }
}
else version (FlintTermNative)
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
