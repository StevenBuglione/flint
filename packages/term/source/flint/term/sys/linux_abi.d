module flint.term.sys.linux_abi;

@system:

// The native terminal session (native/linux.c) is built for Linux and macOS.
version (linux)
    version = FlintTermNative;
else version (OSX)
    version = FlintTermNative;

version (Windows)
    public import flint.term.sys.windows_console : TerminalHandle, flint_term_native_open,
        flint_term_native_tty, flint_term_native_size, flint_term_native_poll,
        flint_term_native_read, flint_term_native_write, flint_term_native_wake,
        flint_term_native_closing, flint_term_native_close, flint_term_native_destroy;
else version (FlintTermNative)
{
package(flint.term):
extern (C) nothrow @nogc:

    struct TerminalHandle;

    int flint_term_native_open(uint modes, TerminalHandle** output);
    int flint_term_native_tty(scope const TerminalHandle* terminal);
    int flint_term_native_size(scope const TerminalHandle* terminal, scope uint* columns, scope uint* rows);
    int flint_term_native_poll(scope const TerminalHandle* terminal, long remainingNanos);
    int flint_term_native_read(scope const TerminalHandle* terminal, scope ubyte* buffer,
            size_t length, scope size_t* count);
    int flint_term_native_write(scope const TerminalHandle* terminal, scope const(char)* buffer, size_t length);
    void flint_term_native_wake(scope TerminalHandle* terminal);
    int flint_term_native_closing(scope const TerminalHandle* terminal);
    int flint_term_native_close(scope TerminalHandle* terminal);
    void flint_term_native_destroy(scope TerminalHandle* terminal);
}
